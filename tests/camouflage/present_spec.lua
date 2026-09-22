-- Presentation mode puts the session into a known state and puts it back, so
-- "is everything masked" is one question rather than five.
describe('camouflage.present', function()
  local present
  local config
  local reveal
  local buffers = {}

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function open(name, lines)
    local bufnr = vim.api.nvim_create_buf(true, false)
    table.insert(buffers, bufnr)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '/' .. name)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    require('camouflage.state').init_buffer(bufnr)
    require('camouflage.core').apply_decorations(bufnr)
    return bufnr
  end

  before_each(function()
    clear_modules()
    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
    })
    config = require('camouflage.config')
    present = require('camouflage.present')
    reveal = require('camouflage.reveal')
    present._reset()
  end)

  after_each(function()
    if present.is_active() then
      present.stop()
    end
    if reveal.is_follow_cursor_enabled() then
      reveal.stop_follow_cursor()
    end
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
  end)

  it('turns masking back on', function()
    config.set('enabled', false)

    assert.is_true(present.start())
    assert.is_true(config.get().enabled)
  end)

  it('turns terminal masking on while it lasts', function()
    assert.is_false(config.get().terminal.enabled)

    present.start()
    assert.is_true(config.get().terminal.enabled)

    present.stop()
    assert.is_false(config.get().terminal.enabled)
  end)

  it('keeps terminal masking on through a project config reload', function()
    present.start()

    assert.is_true((config.reload_project_config()))

    assert.is_true(config.get().terminal.enabled)
  end)

  it('leaves terminal masking to the config again afterwards', function()
    present.start()
    present.stop()

    assert.is_nil(config.runtime_overrides['terminal.enabled'])
    assert.is_true((config.reload_project_config()))
    assert.is_false(config.get().terminal.enabled)
  end)

  it('hides a revealed line and stops follow cursor', function()
    local bufnr = open('present.env', { 'API_KEY=present-secret', 'OTHER=other-secret' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    reveal.reveal_line()
    reveal.start_follow_cursor()
    assert.is_true(reveal.is_follow_cursor_enabled())

    present.start()

    assert.is_false(reveal.is_revealed())
    assert.is_false(reveal.is_follow_cursor_enabled())
    assert.is_true(require('camouflage.state').is_buffer_masked(bufnr))
  end)

  it('masks a buffer where masking had been turned off', function()
    local bufnr = open('off.env', { 'API_KEY=present-secret' })
    vim.b[bufnr].camouflage_enabled = false
    require('camouflage.core').apply_decorations(bufnr)
    assert.is_false(config.is_enabled_for_buffer(bufnr))

    present.start()

    assert.is_true(config.is_enabled_for_buffer(bufnr))
  end)

  it('gives that buffer its override back afterwards', function()
    local bufnr = open('off2.env', { 'API_KEY=present-secret' })
    vim.b[bufnr].camouflage_enabled = false

    present.start()
    present.stop()

    assert.is_false(vim.b[bufnr].camouflage_enabled)
  end)

  it('puts follow cursor back afterwards', function()
    open('follow.env', { 'API_KEY=present-secret', 'OTHER=other-secret' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    reveal.start_follow_cursor()

    present.start()
    assert.is_false(reveal.is_follow_cursor_enabled())

    present.stop()
    assert.is_true(reveal.is_follow_cursor_enabled())
  end)

  it('leaves masking off if that is how it was', function()
    config.set('enabled', false)

    present.start()
    present.stop()

    assert.is_false(config.get().enabled)
    config.set('enabled', true)
  end)

  it('refuses to reveal while it is on', function()
    open('blocked.env', { 'API_KEY=present-secret' })
    present.start()

    assert.is_true(present.block_reveal())
    assert.is_false(reveal.is_revealed())
  end)

  it('allows reveal again once it is off', function()
    present.start()
    present.stop()

    assert.is_false(present.block_reveal())
  end)

  it('says no when it is already on, and when it is already off', function()
    assert.is_true(present.start())
    assert.is_false(present.start())
    assert.is_true(present.stop())
    assert.is_false(present.stop())
  end)

  it('toggles', function()
    assert.is_true(present.toggle())
    assert.is_true(present.is_active())
    assert.is_false(present.toggle())
    assert.is_false(present.is_active())
  end)

  it('reports what it is doing', function()
    assert.equals('off', present.status())

    open('status.env', { 'API_KEY=present-secret' })
    present.start()

    assert.is_not_nil(present.status():find('^on,'))
  end)

  describe('with a buffer from another repository', function()
    local root
    local opened = {}

    -- Repo B turns masking off in its own project file, repo A has one that
    -- changes nothing. Neither is the project of the working directory.
    before_each(function()
      root = vim.fn.tempname()
      for _, repo in ipairs({ 'a', 'b' }) do
        vim.fn.mkdir(root .. '/' .. repo, 'p')
        vim.fn.writefile({ 'API_KEY=' .. repo .. '-secret' }, root .. '/' .. repo .. '/.env')
      end
      vim.fn.writefile({ 'version: 1' }, root .. '/a/.camouflage.yaml')
      vim.fn.writefile({ 'version: 1', 'enabled: false' }, root .. '/b/.camouflage.yaml')

      clear_modules()
      local notify = vim.notify_once
      vim.notify_once = function() end
      require('camouflage').setup({
        project_config = { watch_enabled = false },
        reveal = { notify = false },
      })
      vim.notify_once = notify
      config = require('camouflage.config')
      present = require('camouflage.present')
      reveal = require('camouflage.reveal')
      present._reset()
    end)

    after_each(function()
      if present.is_active() then
        present.stop()
      end
      for _, bufnr in ipairs(opened) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      opened = {}
      vim.fn.delete(root, 'rf')
    end)

    local function edit(repo)
      vim.cmd('edit! ' .. vim.fn.fnameescape(root .. '/' .. repo .. '/.env'))
      local bufnr = vim.api.nvim_get_current_buf()
      table.insert(opened, bufnr)
      return bufnr
    end

    local function marks(bufnr)
      local ns = require('camouflage.state').namespace
      return #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    end

    it('masks it while shown', function()
      local b = edit('b')
      assert.equals(0, marks(b))

      present.start()

      assert.equals(1, marks(b))
    end)

    it('masks it when it is shown again', function()
      local b = edit('b')
      local a = edit('a')
      assert.equals(1, marks(a))

      present.start()
      vim.cmd('buffer ' .. b)

      assert.equals(1, marks(b))
    end)

    it('gives it its own setting back afterwards', function()
      local b = edit('b')
      present.start()
      assert.equals(1, marks(b))

      present.stop()

      assert.equals(0, marks(b))
      assert.is_nil(config.runtime_enabled)
    end)
  end)
end)
