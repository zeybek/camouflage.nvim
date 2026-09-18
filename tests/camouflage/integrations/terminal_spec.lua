-- Terminal output has no file behind it, so there is no parser and no key
-- structure, only the shape of a line. That is why this is off by default and
-- limited to keys that already look sensitive.
describe('camouflage.integrations.terminal', function()
  local terminal
  local config
  local buffers = {}

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  ---A real terminal buffer with text in it, without a process: nvim_open_term
  ---turns the buffer into one and takes the output over a channel.
  local function terminal_with(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(buffers, bufnr)
    local chan = vim.api.nvim_open_term(bufnr, {})
    vim.api.nvim_chan_send(chan, table.concat(lines, '\r\n') .. '\r\n')
    vim.wait(200, function()
      return (vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or '') ~= ''
    end, 5)
    return bufnr
  end

  ---What each row would be covered with, walking rows the way a redraw does.
  local function drawn(bufnr)
    local covered = {}
    terminal.on_win(bufnr)
    for row = 0, vim.api.nvim_buf_line_count(bufnr) - 1 do
      local _, value = terminal.on_line(bufnr, row)
      covered[row] = value
    end
    return covered
  end

  before_each(function()
    clear_modules()
    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
      terminal = { enabled = true },
    })
    config = require('camouflage.config')
    terminal = require('camouflage.integrations.terminal')
    terminal._reset()
  end)

  after_each(function()
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
  end)

  describe('line_key', function()
    it('reads the key off a printed assignment', function()
      assert.equals('API_KEY', terminal.line_key('API_KEY=value'))
      assert.equals('db_password', terminal.line_key('  db_password: value'))
      assert.equals('TOKEN', terminal.line_key('ENV TOKEN=value'))
    end)

    it('returns nothing for a line with no key at all', function()
      assert.is_nil(terminal.line_key('  at Object.<anonymous> (index.js:1)'))
      assert.is_nil(terminal.line_key('Building project...'))
      assert.is_nil(terminal.line_key(''))
    end)

    it('reads past a comment marker and a shell export', function()
      -- The line-level matcher already sees through both, so a key behind one
      -- has to reach the sensitive list the same way a bare one does.
      assert.equals('OLD_API_KEY', terminal.line_key('# OLD_API_KEY=deprecated_key_12345'))
      assert.equals('GITHUB_TOKEN', terminal.line_key('export GITHUB_TOKEN=ghp_yyyyyyyyyyyyyyyy'))
      assert.equals('DB_PASSWORD', terminal.line_key('  ;; DB_PASSWORD=hunter2'))
      assert.is_true(terminal.should_mask('# OLD_API_KEY=deprecated_key_12345'))
      assert.is_true(terminal.should_mask('export GITHUB_TOKEN=ghp_yyyyyyyyyyyyyyyy'))
    end)

    it('leaves a word that merely starts with export alone', function()
      assert.equals('exported', terminal.line_key('exported: true'))
    end)

    it('reads build output as a key too, which is why keys are filtered', function()
      -- `make: build=release` has the shape of an assignment. The sensitive-key
      -- filter is what keeps it visible, not the shape.
      assert.equals('make', terminal.line_key('make: build=release'))
      assert.is_false(terminal.should_mask('make: build=release'))
    end)
  end)

  describe('holds_credentials', function()
    it('covers a value carrying a password, whatever the key is called', function()
      -- `database_url` is not a sensitive key and should not become one, or
      -- every `API_URL=` line in build output starts getting stars.
      local line = 'DATABASE_URL=postgres://user:password123@localhost:5432/mydb'
      assert.is_true(terminal.holds_credentials(line))
      assert.is_true(terminal.should_mask(line))
      assert.is_true(terminal.should_mask('conn = mongodb+srv://admin:s3cret@cluster0.example.net'))
    end)

    it('leaves a URL with no credentials in it readable', function()
      assert.is_false(terminal.holds_credentials('API_URL=https://api.example.com/v1'))
      assert.is_false(terminal.should_mask('API_URL=https://api.example.com/v1'))
      assert.is_false(terminal.holds_credentials('repo: https://github.com/zeybek/camouflage.nvim'))
    end)
  end)

  it('covers lines whose key looks sensitive', function()
    local bufnr = terminal_with({
      'API_KEY=sk_live_terminal_secret',
      'DB_PASSWORD=hunter2',
      'HOME=/Users/demo',
      'make: build=release',
    })

    local covered = drawn(bufnr)
    assert.equals('sk_live_terminal_secret', covered[0])
    assert.equals('hunter2', covered[1])
    assert.is_nil(covered[2])
    assert.is_nil(covered[3])
  end)

  it('covers a printed .env the way the buffer does', function()
    -- `:terminal cat .env` next to the file used to show values the buffer hid.
    local bufnr = terminal_with({
      'DATABASE_URL=postgres://user:password123@localhost:5432/mydb',
      '# OLD_API_KEY=deprecated_key_12345',
      'export GITHUB_TOKEN=ghp_yyyyyyyyyyyyyyyy',
      'NODE_ENV=development',
    })

    local covered = drawn(bufnr)
    assert.equals('postgres://user:password123@localhost:5432/mydb', covered[0])
    assert.equals('deprecated_key_12345', covered[1])
    assert.equals('ghp_yyyyyyyyyyyyyyyy', covered[2])
    assert.is_nil(covered[3])
  end)

  it('covers every assignment when asked to', function()
    config.set('terminal.keys', 'all')
    local bufnr = terminal_with({ 'HOME=/Users/demo', 'Building project...' })

    local covered = drawn(bufnr)
    assert.equals('/Users/demo', covered[0])
    assert.is_nil(covered[1], 'a line with no key is still left alone')
    config.set('terminal.keys', 'sensitive')
  end)

  it('takes its own key patterns when given some', function()
    config.set('terminal.key_patterns', { 'licence' })
    local bufnr = terminal_with({ 'LICENCE_KEY=abcdef', 'API_KEY=sk_live_x' })

    local covered = drawn(bufnr)
    assert.equals('abcdef', covered[0])
    assert.is_nil(covered[1], 'the default list no longer applies')
    config.set('terminal.key_patterns', nil)
  end)

  describe('on_win', function()
    it('takes terminal buffers', function()
      assert.is_true(terminal.on_win(terminal_with({ 'API_KEY=x' })))
    end)

    it('skips ordinary buffers', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      table.insert(buffers, bufnr)
      assert.is_false(terminal.on_win(bufnr))
    end)

    it('skips a terminal the user turned off', function()
      local bufnr = terminal_with({ 'API_KEY=x' })
      vim.b[bufnr].camouflage_terminal = false

      assert.is_false(terminal.on_win(bufnr))
    end)

    it('is off unless it was turned on', function()
      config.set('terminal.enabled', false)
      assert.is_false(terminal.on_win(terminal_with({ 'API_KEY=x' })))
      config.set('terminal.enabled', true)
    end)

    it('follows the global switch', function()
      config.set('enabled', false)
      assert.is_false(terminal.on_win(terminal_with({ 'API_KEY=x' })))
      config.set('enabled', true)
    end)
  end)

  it('is off in the default config', function()
    clear_modules()
    require('camouflage').setup({ project_config = { enabled = false, watch_enabled = false } })

    assert.is_false(require('camouflage.config').get().terminal.enabled)
  end)
end)
