describe('camouflage.reveal', function()
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
    -- Use unique filename to avoid E95 error
    local unique_name = filename and (filename .. '.' .. test_counter)
      or ('/tmp/test_' .. test_counter .. '.env')
    vim.api.nvim_buf_set_name(bufnr, unique_name)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  before_each(function()
    clear_camouflage_modules()
    require('camouflage').setup({
      reveal = {
        notify = false,
      },
    })
    reveal = require('camouflage.reveal')
    state = require('camouflage.state')
    hooks = require('camouflage.hooks')
  end)

  after_each(function()
    -- Cleanup any revealed state
    if reveal.is_revealed() then
      reveal.hide()
    end
  end)

  describe('reveal_line', function()
    it('reveals values on current line', function()
      local bufnr = setup_test_buffer('API_KEY=secret123\nDEBUG=true', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 16 },
        { key = 'DEBUG', value = 'true', start_index = 24, end_index = 27 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.reveal_line()

      assert.is_true(reveal.is_revealed())
      local revealed = reveal.get_revealed()
      assert.equals(bufnr, revealed.bufnr)
      assert.equals(1, revealed.line)
    end)

    it('does nothing if already revealed on same line', function()
      local bufnr = setup_test_buffer('API_KEY=secret123', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 16 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.reveal_line()
      reveal.reveal_line() -- Second call should be no-op

      assert.is_true(reveal.is_revealed())
    end)

    it('hides previous reveal before revealing new line', function()
      local bufnr = setup_test_buffer('A=1\nB=2', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 2 },
        { key = 'B', value = '2', start_index = 6, end_index = 6 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.reveal_line()
      assert.equals(1, reveal.get_revealed().line)

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      reveal.reveal_line()
      assert.equals(2, reveal.get_revealed().line)
    end)

    it('shows warning when no variables in buffer', function()
      setup_test_buffer('no secrets', '/tmp/test.txt')

      local warned = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end

      reveal.reveal_line()

      vim.notify = original_notify
      assert.is_true(warned)
      assert.is_false(reveal.is_revealed())
    end)
  end)

  describe('hide', function()
    it('clears revealed state', function()
      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 2 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.reveal_line()
      assert.is_true(reveal.is_revealed())

      reveal.hide()
      assert.is_false(reveal.is_revealed())
      assert.is_nil(reveal.get_revealed())
    end)

    it('does nothing if not revealed', function()
      assert.has_no.errors(function()
        reveal.hide()
      end)
    end)
  end)

  describe('toggle', function()
    it('reveals if not revealed', function()
      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 2 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.toggle()

      assert.is_true(reveal.is_revealed())
    end)

    it('hides if already revealed on same line', function()
      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 2 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.toggle()
      assert.is_true(reveal.is_revealed())

      reveal.toggle()
      assert.is_false(reveal.is_revealed())
    end)
  end)

  describe('hooks', function()
    it('emits before_reveal event', function()
      local event_fired = false
      hooks.on('before_reveal', function()
        event_fired = true
      end)

      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 2 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.reveal_line()

      assert.is_true(event_fired)
    end)

    it('cancels reveal when before_reveal returns false', function()
      hooks.on('before_reveal', function()
        return false
      end)

      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 2 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.reveal_line()

      assert.is_false(reveal.is_revealed())
    end)

    it('emits after_reveal event', function()
      local event_fired = false
      local event_line = nil

      hooks.on('after_reveal', function(bufnr, line)
        event_fired = true
        event_line = line
      end)

      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 2 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.reveal_line()

      assert.is_true(event_fired)
      assert.equals(1, event_line)
    end)
  end)

  describe('is_revealed', function()
    it('returns false when nothing is revealed', function()
      assert.is_false(reveal.is_revealed())
    end)

    it('returns true when something is revealed', function()
      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 2 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.reveal_line()

      assert.is_true(reveal.is_revealed())
    end)
  end)

  describe('get_revealed', function()
    it('returns nil when nothing is revealed', function()
      assert.is_nil(reveal.get_revealed())
    end)

    it('returns bufnr and line when revealed', function()
      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 2 },
      })

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.reveal_line()

      local revealed = reveal.get_revealed()
      assert.is_not_nil(revealed)
      assert.equals(bufnr, revealed.bufnr)
      assert.equals(1, revealed.line)
    end)
  end)
end)
