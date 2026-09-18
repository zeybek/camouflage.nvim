-- A diff shows the old and the new value of every changed line, so hunks of a
-- file a parser handles get their values covered. Which file a row belongs to
-- comes from the header above it, so a diff of a source file stays readable.
describe('camouflage.integrations.diff', function()
  local diff
  local config
  local bufnr

  local DIFF = {
    'diff --git a/.env b/.env',
    'index 05a13ff..426d31a 100644',
    '--- a/.env',
    '+++ b/.env',
    '@@ -1,2 +1,3 @@',
    '-API_KEY=old-secret',
    '+API_KEY=new-secret',
    ' DEBUG=true',
    '+DB_PASSWORD=hunter2-but-longer',
    'diff --git a/app.lua b/app.lua',
    '--- a/app.lua',
    '+++ b/app.lua',
    '@@ -1 +1 @@',
    '-local retries = 1',
    '+local retries = 2',
  }

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function open(lines, filetype)
    bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = filetype or 'diff'
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  ---Walk the rows the way a redraw does, collecting what each one covered.
  local function drawn(buf, from, to)
    local covered = {}
    diff.on_win(buf, from)
    for row = from, to do
      local col, value = diff.on_line(buf, row)
      covered[row] = col and value or nil
    end
    return covered
  end

  before_each(function()
    clear_modules()
    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
    })
    config = require('camouflage.config')
    diff = require('camouflage.integrations.diff')
    diff._reset()
  end)

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    bufnr = nil
  end)

  describe('header_file', function()
    it('reads the file out of the headers', function()
      assert.equals('.env', diff.header_file('diff --git a/.env b/.env'))
      assert.equals('config/values.yaml', diff.header_file('+++ b/config/values.yaml'))
      assert.equals('.env', diff.header_file('+++ .env\t2026-09-18 10:00:00'))
    end)

    it('marks headers that name no file', function()
      local file, is_header = diff.header_file('+++ /dev/null')
      assert.is_nil(file)
      assert.is_true(is_header)

      file, is_header = diff.header_file('--- a/.env')
      assert.is_nil(file)
      assert.is_true(is_header)
    end)

    it('leaves content lines alone', function()
      local file, is_header = diff.header_file('-API_KEY=old-secret')
      assert.is_nil(file)
      assert.is_false(is_header)
    end)
  end)

  describe('row_value', function()
    it('finds the value after the diff marker', function()
      local col, value = diff.row_value('-API_KEY=old-secret')
      assert.equals(9, col)
      assert.equals('old-secret', value)

      col, value = diff.row_value(' DEBUG=true')
      assert.equals(7, col)
      assert.equals('true', value)
    end)

    it('skips headers and hunk markers', function()
      assert.is_nil(diff.row_value('+++ b/.env'))
      assert.is_nil(diff.row_value('--- a/.env'))
      assert.is_nil(diff.row_value('@@ -1,2 +1,3 @@'))
      assert.is_nil(diff.row_value('diff --git a/.env b/.env'))
    end)

    it('leaves a line that carries no value', function()
      assert.is_nil(diff.row_value('-local retries = 1'))
    end)
  end)

  describe('file_at', function()
    it('finds the file a row belongs to', function()
      local buf = open(DIFF)
      assert.equals('.env', diff.file_at(buf, 5))
      assert.equals('.env', diff.file_at(buf, 8))
      assert.equals('app.lua', diff.file_at(buf, 13))
    end)

    it('returns nothing above the first header', function()
      local buf = open({ 'commit message', '', '# Please enter the commit message' }, 'gitcommit')
      assert.is_nil(diff.file_at(buf, 2))
    end)
  end)

  it('covers the values of a supported file and nothing else', function()
    local buf = open(DIFF)
    local covered = drawn(buf, 0, #DIFF - 1)

    assert.equals('old-secret', covered[5])
    assert.equals('new-secret', covered[6])
    assert.equals('true', covered[7])
    assert.equals('hunter2-but-longer', covered[8])

    for _, row in ipairs({ 0, 1, 2, 3, 4, 9, 10, 11, 12, 13, 14 }) do
      assert.is_nil(covered[row], ('row %d should be left alone'):format(row))
    end
  end)

  it('keeps masking when the window starts inside a hunk', function()
    local buf = open(DIFF)
    local covered = drawn(buf, 6, 8)

    assert.equals('new-secret', covered[6])
    assert.equals('hunter2-but-longer', covered[8])
  end)

  it('masks the diff under a commit message', function()
    local buf = open({
      'env: rotate the api key',
      '',
      '# Please enter the commit message for your changes.',
      'diff --git a/.env b/.env',
      '--- a/.env',
      '+++ b/.env',
      '@@ -1 +1 @@',
      '+API_KEY=committed-secret',
    }, 'gitcommit')

    local covered = drawn(buf, 0, 7)
    assert.equals('committed-secret', covered[7])
    assert.is_nil(covered[0])
    assert.is_nil(covered[2])
  end)

  describe('on_win', function()
    it('takes diff, gitcommit and git buffers', function()
      for _, filetype in ipairs({ 'diff', 'gitcommit', 'git', 'fugitive' }) do
        local buf = open(DIFF, filetype)
        assert.is_true(diff.on_win(buf, 0), filetype .. ' should be handled')
        vim.api.nvim_buf_delete(buf, { force = true })
      end
      bufnr = nil
    end)

    it('skips other buffers', function()
      local buf = open(DIFF, 'lua')
      assert.is_false(diff.on_win(buf, 0))
    end)

    it('skips while the integration is off', function()
      config.set('integrations.diff', false)
      local buf = open(DIFF)
      assert.is_false(diff.on_win(buf, 0))
      config.set('integrations.diff', true)
    end)

    it('skips while masking is off', function()
      config.set('enabled', false)
      local buf = open(DIFF)
      assert.is_false(diff.on_win(buf, 0))
      config.set('enabled', true)
    end)
  end)
end)
