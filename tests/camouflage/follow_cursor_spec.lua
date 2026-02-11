describe('camouflage.reveal follow_cursor', function()
  local reveal
  local state
  local hooks
  local test_counter = 0

  local function clear_camouflage_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function setup_test_buffer(content, filename)
    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, '\n'))
    local unique_name = filename and (filename .. '.' .. test_counter)
      or ('/tmp/test_follow_' .. test_counter .. '.env')
    vim.api.nvim_buf_set_name(bufnr, unique_name)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  before_each(function()
    clear_camouflage_modules()
    require('camouflage').setup({
      reveal = {
        notify = false,
        follow_cursor = false,
      },
    })
    reveal = require('camouflage.reveal')
    state = require('camouflage.state')
    hooks = require('camouflage.hooks')
  end)

  after_each(function()
    -- Cleanup follow cursor mode
    if reveal.is_follow_cursor_enabled() then
      reveal.stop_follow_cursor()
    end
    -- Cleanup any revealed state
    if reveal.is_revealed() then
      reveal.hide()
    end
  end)

  describe('is_follow_cursor_enabled', function()
    it('returns false by default', function()
      assert.is_false(reveal.is_follow_cursor_enabled())
    end)

    it('returns true after starting follow mode', function()
      reveal.start_follow_cursor()
      assert.is_true(reveal.is_follow_cursor_enabled())
    end)
  end)

  describe('start_follow_cursor', function()
    it('enables follow cursor mode', function()
      reveal.start_follow_cursor()
      assert.is_true(reveal.is_follow_cursor_enabled())
    end)

    it('does nothing if already enabled', function()
      reveal.start_follow_cursor()
      reveal.start_follow_cursor() -- Second call should be no-op
      assert.is_true(reveal.is_follow_cursor_enabled())
    end)

    it('reveals current line immediately if it has variables', function()
      local bufnr = setup_test_buffer('API_KEY=secret123', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 16 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.start_follow_cursor()

      assert.is_true(reveal.is_revealed())
      local revealed = reveal.get_revealed()
      assert.equals(1, revealed.line)
    end)
  end)

  describe('stop_follow_cursor', function()
    it('disables follow cursor mode', function()
      reveal.start_follow_cursor()
      reveal.stop_follow_cursor()
      assert.is_false(reveal.is_follow_cursor_enabled())
    end)

    it('hides any active reveal', function()
      local bufnr = setup_test_buffer('API_KEY=secret123', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 16 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.start_follow_cursor()
      assert.is_true(reveal.is_revealed())

      reveal.stop_follow_cursor()
      assert.is_false(reveal.is_revealed())
    end)

    it('does nothing if not enabled', function()
      assert.has_no.errors(function()
        reveal.stop_follow_cursor()
      end)
    end)
  end)

  describe('toggle_follow_cursor', function()
    it('enables when disabled', function()
      reveal.toggle_follow_cursor()
      assert.is_true(reveal.is_follow_cursor_enabled())
    end)

    it('disables when enabled', function()
      reveal.start_follow_cursor()
      reveal.toggle_follow_cursor()
      assert.is_false(reveal.is_follow_cursor_enabled())
    end)

    it('force disables with force_disable option', function()
      reveal.start_follow_cursor()
      reveal.toggle_follow_cursor({ force_disable = true })
      assert.is_false(reveal.is_follow_cursor_enabled())
    end)

    it('force disable does nothing when already disabled', function()
      reveal.toggle_follow_cursor({ force_disable = true })
      assert.is_false(reveal.is_follow_cursor_enabled())
    end)
  end)

  describe('hooks', function()
    it('emits before_follow_start event', function()
      local event_fired = false
      hooks.on('before_follow_start', function()
        event_fired = true
      end)

      reveal.start_follow_cursor()
      assert.is_true(event_fired)
    end)

    it('cancels start when before_follow_start returns false', function()
      hooks.on('before_follow_start', function()
        return false
      end)

      reveal.start_follow_cursor()
      assert.is_false(reveal.is_follow_cursor_enabled())
    end)

    it('emits after_follow_start event', function()
      local event_fired = false
      hooks.on('after_follow_start', function()
        event_fired = true
      end)

      reveal.start_follow_cursor()
      assert.is_true(event_fired)
    end)

    it('emits before_follow_stop event', function()
      local event_fired = false
      hooks.on('before_follow_stop', function()
        event_fired = true
      end)

      reveal.start_follow_cursor()
      reveal.stop_follow_cursor()
      assert.is_true(event_fired)
    end)

    it('cancels stop when before_follow_stop returns false', function()
      hooks.on('before_follow_stop', function()
        return false
      end)

      reveal.start_follow_cursor()
      reveal.stop_follow_cursor()
      -- Should still be enabled because stop was cancelled
      assert.is_true(reveal.is_follow_cursor_enabled())
    end)

    it('emits after_follow_stop event', function()
      local event_fired = false
      hooks.on('after_follow_stop', function()
        event_fired = true
      end)

      reveal.start_follow_cursor()
      reveal.stop_follow_cursor()
      assert.is_true(event_fired)
    end)
  end)

  describe('cursor movement behavior', function()
    it('does not reveal lines without variables', function()
      local bufnr = setup_test_buffer('no secrets here\njust text', '/tmp/test.env')
      state.set_variables(bufnr, {})

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.start_follow_cursor()

      assert.is_false(reveal.is_revealed())
    end)

    it('reveals line when it has variables', function()
      local bufnr = setup_test_buffer('API_KEY=secret\nDEBUG=true', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret', start_index = 8, end_index = 13 },
        { key = 'DEBUG', value = 'true', start_index = 21, end_index = 24 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.start_follow_cursor()

      assert.is_true(reveal.is_revealed())
      assert.equals(1, reveal.get_revealed().line)
    end)
  end)

  describe('API exposure', function()
    it('is accessible from main camouflage module', function()
      local camouflage = require('camouflage')

      assert.is_function(camouflage.start_follow_cursor)
      assert.is_function(camouflage.stop_follow_cursor)
      assert.is_function(camouflage.toggle_follow_cursor)
      assert.is_function(camouflage.is_follow_cursor_enabled)
    end)

    it('works via main module API', function()
      local camouflage = require('camouflage')

      assert.is_false(camouflage.is_follow_cursor_enabled())
      camouflage.start_follow_cursor()
      assert.is_true(camouflage.is_follow_cursor_enabled())
      camouflage.stop_follow_cursor()
      assert.is_false(camouflage.is_follow_cursor_enabled())
    end)
  end)

  describe('config auto-start', function()
    it('does not auto-start when follow_cursor is false', function()
      clear_camouflage_modules()
      require('camouflage').setup({
        reveal = {
          follow_cursor = false,
        },
      })

      -- Need to wait for vim.schedule
      vim.wait(100, function()
        return false
      end)

      reveal = require('camouflage.reveal')
      assert.is_false(reveal.is_follow_cursor_enabled())
    end)
  end)
end)
