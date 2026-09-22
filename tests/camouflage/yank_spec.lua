describe('camouflage.yank', function()
  local yank
  local state
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
      yank = {
        confirm = false, -- Disable confirmation for tests
        notify = false, -- Disable notifications for tests
        auto_clear_seconds = nil, -- Disable auto-clear for tests
        default_register = 'z', -- Use 'z' register to avoid clipboard provider issues
      },
    })
    yank = require('camouflage.yank')
    state = require('camouflage.state')
  end)

  after_each(function()
    yank.cancel_auto_clear()
    -- Clear test registers
    vim.fn.setreg('z', '')
    vim.fn.setreg('a', '')
  end)

  describe('find_variable_at_cursor', function()
    it('returns nil when buffer has no variables', function()
      setup_test_buffer('just some text', '/tmp/test.txt')
      local result = yank.find_variable_at_cursor()
      assert.is_nil(result)
    end)

    it('returns nil when cursor is not on a variable', function()
      local bufnr = setup_test_buffer('API_KEY=secret123\nDEBUG=true', '/tmp/test.env')
      -- Set variables manually for testing
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 17 },
        { key = 'DEBUG', value = 'true', start_index = 24, end_index = 28 },
      })
      -- Position cursor on an empty line (if we had one)
      vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- At 'A' of API_KEY
      -- This should still find it since it's on the same line
      local result = yank.find_variable_at_cursor()
      assert.is_not_nil(result)
    end)

    it('returns variable when cursor is on masked value', function()
      local bufnr = setup_test_buffer('API_KEY=secret123', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 17 },
      })
      vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- On 'secret123'
      local result = yank.find_variable_at_cursor()
      assert.is_not_nil(result)
      assert.equals('API_KEY', result.key)
    end)

    it('returns variable when cursor is on same line', function()
      local bufnr = setup_test_buffer('API_KEY=secret123', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 17 },
      })
      vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- At beginning of line
      local result = yank.find_variable_at_cursor()
      assert.is_not_nil(result)
      assert.equals('API_KEY', result.key)
    end)

    it('returns nearest same-line variable when cursor is just after the value', function()
      local bufnr = setup_test_buffer('API_KEY=secret123,', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 17 },
      })
      vim.api.nvim_win_set_cursor(0, { 1, 17 }) -- comma after the value

      local result = yank.find_variable_at_cursor()

      assert.is_not_nil(result)
      assert.equals('API_KEY', result.key)
    end)
  end)

  describe('do_yank', function()
    it('copies value to default register', function()
      setup_test_buffer('API_KEY=secret123', '/tmp/test.env')
      local var = { key = 'API_KEY', value = 'secret123' }
      yank.do_yank(var)
      assert.equals('secret123', vim.fn.getreg('z'))
    end)

    it('copies value to specified register', function()
      setup_test_buffer('API_KEY=secret123', '/tmp/test.env')
      local var = { key = 'API_KEY', value = 'secret123' }
      yank.do_yank(var, { register = 'a' })
      assert.equals('secret123', vim.fn.getreg('a'))
    end)

    it('handles empty value', function()
      setup_test_buffer('API_KEY=', '/tmp/test.env')
      local var = { key = 'API_KEY', value = '' }
      yank.do_yank(var)
      assert.equals('', vim.fn.getreg('z'))
    end)

    it('handles multiline value', function()
      local multiline = 'line1\nline2\nline3'
      setup_test_buffer('KEY=' .. multiline, '/tmp/test.env')
      local var = { key = 'KEY', value = multiline }
      yank.do_yank(var)
      assert.equals(multiline, vim.fn.getreg('z'))
    end)
  end)

  describe('yank (hybrid)', function()
    it('uses cursor when on variable', function()
      local bufnr = setup_test_buffer('API_KEY=secret123', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 17 },
      })
      vim.api.nvim_win_set_cursor(0, { 1, 10 })

      -- Mock vim.ui.select to track if it was called
      local picker_called = false
      local original_select = vim.ui.select
      vim.ui.select = function(...)
        picker_called = true
        original_select(...)
      end

      yank.yank()

      vim.ui.select = original_select

      assert.is_false(picker_called)
      assert.equals('secret123', vim.fn.getreg('z'))
    end)

    it('shows picker when not on variable line', function()
      local bufnr = setup_test_buffer('# Comment\nAPI_KEY=secret123', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 18, end_index = 27 },
      })
      vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- On comment line

      local picker_called = false
      local original_select = vim.ui.select
      vim.ui.select = function(items, opts, callback)
        picker_called = true
        -- Simulate selecting first item
        callback(items[1])
      end

      yank.yank()

      vim.ui.select = original_select

      assert.is_true(picker_called)
    end)

    it('forces picker with force_picker option', function()
      local bufnr = setup_test_buffer('API_KEY=secret123', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 17 },
      })
      vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- On the value

      local picker_called = false
      local original_select = vim.ui.select
      vim.ui.select = function(items, opts, callback)
        picker_called = true
        callback(items[1])
      end

      yank.yank({ force_picker = true })

      vim.ui.select = original_select

      assert.is_true(picker_called)
    end)

    it('shows warning when no variables in buffer', function()
      setup_test_buffer('no secrets here', '/tmp/test.txt')

      local notify_called = false
      local notify_level = nil
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        notify_called = true
        notify_level = level
      end

      yank.yank()

      vim.notify = original_notify

      assert.is_true(notify_called)
      assert.equals(vim.log.levels.WARN, notify_level)
    end)
  end)

  describe('yank_with_picker', function()
    it('shows all variables in picker', function()
      local bufnr = setup_test_buffer('A=1\nB=2\nC=3', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 3 },
        { key = 'B', value = '2', start_index = 6, end_index = 7 },
        { key = 'C', value = '3', start_index = 10, end_index = 11 },
      })

      local picker_items = nil
      local original_select = vim.ui.select
      vim.ui.select = function(items, opts, callback)
        picker_items = items
        callback(nil) -- Cancel
      end

      yank.yank_with_picker()

      vim.ui.select = original_select

      assert.equals(3, #picker_items)
      assert.equals('A', picker_items[1].label)
      assert.equals('B', picker_items[2].label)
      assert.equals('C', picker_items[3].label)
    end)

    it('does not show values in picker items', function()
      local bufnr = setup_test_buffer('SECRET=mysecretvalue', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'SECRET', value = 'mysecretvalue', start_index = 7, end_index = 20 },
      })

      local formatted_item = nil
      local original_select = vim.ui.select
      vim.ui.select = function(items, opts, callback)
        formatted_item = opts.format_item(items[1])
        callback(nil)
      end

      yank.yank_with_picker()

      vim.ui.select = original_select

      -- Should contain key but NOT the value
      assert.is_truthy(formatted_item:match('SECRET'))
      assert.is_falsy(formatted_item:match('mysecretvalue'))
    end)

    it('handles user cancellation', function()
      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 3 },
      })

      local original_select = vim.ui.select
      vim.ui.select = function(items, opts, callback)
        callback(nil) -- User cancelled
      end

      vim.fn.setreg('z', 'original')
      yank.yank_with_picker()

      vim.ui.select = original_select

      -- Clipboard should be unchanged
      assert.equals('original', vim.fn.getreg('z'))
    end)
  end)

  describe('confirmation', function()
    it('prompts when confirm is enabled', function()
      clear_camouflage_modules()
      require('camouflage').setup({
        yank = {
          confirm = true,
          notify = false,
          auto_clear_seconds = nil,
          default_register = 'z',
        },
      })
      yank = require('camouflage.yank')
      state = require('camouflage.state')

      local bufnr = setup_test_buffer('A=1', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = '1', start_index = 2, end_index = 3 },
      })

      local confirm_shown = false
      local original_select = vim.ui.select
      vim.ui.select = function(items, opts, callback)
        if items[1] == 'Yes' then
          confirm_shown = true
          callback('Yes')
        else
          callback(items[1])
        end
      end

      vim.api.nvim_win_set_cursor(0, { 1, 2 })
      yank.yank()

      vim.ui.select = original_select

      assert.is_true(confirm_shown)
    end)

    it('does not copy when user selects No', function()
      clear_camouflage_modules()
      require('camouflage').setup({
        yank = {
          confirm = true,
          notify = false,
          auto_clear_seconds = nil,
          default_register = 'z',
        },
      })
      yank = require('camouflage.yank')
      state = require('camouflage.state')

      local bufnr = setup_test_buffer('A=secret', '/tmp/test.env')
      state.set_variables(bufnr, {
        { key = 'A', value = 'secret', start_index = 2, end_index = 8 },
      })

      local original_select = vim.ui.select
      vim.ui.select = function(items, opts, callback)
        if items[1] == 'Yes' then
          callback('No') -- User selects No
        end
      end

      vim.fn.setreg('z', 'original')
      vim.api.nvim_win_set_cursor(0, { 1, 2 })
      yank.yank()

      vim.ui.select = original_select

      assert.equals('original', vim.fn.getreg('z'))
    end)
  end)

  describe('hooks', function()
    it('emits before_yank event', function()
      local hooks = require('camouflage.hooks')
      local event_fired = false
      local event_var = nil

      hooks.on('before_yank', function(bufnr, var)
        event_fired = true
        event_var = var
      end)

      setup_test_buffer('A=1', '/tmp/test.env')
      local var = { key = 'A', value = '1' }
      yank.do_yank(var)

      assert.is_true(event_fired)
      assert.equals('A', event_var.key)
    end)

    it('cancels yank when before_yank returns false', function()
      local hooks = require('camouflage.hooks')

      hooks.on('before_yank', function()
        return false
      end)

      vim.fn.setreg('z', 'original')
      setup_test_buffer('A=secret', '/tmp/test.env')
      local var = { key = 'A', value = 'secret' }
      yank.do_yank(var)

      assert.equals('original', vim.fn.getreg('z'))
    end)

    it('emits after_yank event', function()
      local hooks = require('camouflage.hooks')
      local event_fired = false
      local event_register = nil

      hooks.on('after_yank', function(bufnr, var, register)
        event_fired = true
        event_register = register
      end)

      setup_test_buffer('A=1', '/tmp/test.env')
      local var = { key = 'A', value = '1' }
      yank.do_yank(var, { register = 'a' })

      assert.is_true(event_fired)
      assert.equals('a', event_register)
    end)
  end)

  describe('auto-clear', function()
    it('clears the register after the delay when it still holds the secret', function()
      vim.fn.setreg('a', 'secretA')
      yank.schedule_auto_clear('a', 0.05, 'secretA')
      vim.wait(400, function()
        return vim.fn.getreg('a') == ''
      end)
      assert.equals('', vim.fn.getreg('a'))
    end)

    it('does not wipe the register when its contents have changed', function()
      vim.fn.setreg('a', 'secretA')
      yank.schedule_auto_clear('a', 0.05, 'secretA')
      vim.fn.setreg('a', 'user typed this') -- user reused the register
      vim.wait(200)
      assert.equals('user typed this', vim.fn.getreg('a'))
    end)

    it('uses independent timers per register', function()
      vim.fn.setreg('a', 'secretA')
      vim.fn.setreg('z', 'secretZ')
      yank.schedule_auto_clear('a', 0.05, 'secretA')
      -- A second yank to a different register must not cancel the first timer.
      yank.schedule_auto_clear('z', 0.05, 'secretZ')
      vim.wait(400, function()
        return vim.fn.getreg('a') == '' and vim.fn.getreg('z') == ''
      end)
      assert.equals('', vim.fn.getreg('a'))
      assert.equals('', vim.fn.getreg('z'))
    end)
  end)

  describe('auto-clear when Neovim exits first', function()
    local function leave()
      vim.api.nvim_exec_autocmds('VimLeavePre', {})
    end

    it('clears a register whose timer has not fired yet', function()
      vim.fn.setreg('a', 'exit-secret')
      yank.schedule_auto_clear('a', 30, 'exit-secret')

      leave()

      assert.equals('', vim.fn.getreg('a'))
    end)

    it('leaves a register the user reused alone', function()
      vim.fn.setreg('a', 'exit-secret')
      yank.schedule_auto_clear('a', 30, 'exit-secret')
      vim.fn.setreg('a', 'typed later')

      leave()

      assert.equals('typed later', vim.fn.getreg('a'))
    end)

    it('restores what an uppercase register appended to', function()
      vim.fn.setreg('b', 'previous-')
      local previous = { value = vim.fn.getreg('b', 1, true), regtype = vim.fn.getregtype('b') }
      vim.fn.setreg('B', 'exit-secret')
      yank.schedule_auto_clear('B', 30, 'exit-secret', previous)

      leave()

      assert.equals('previous-', vim.fn.getreg('b'))
    end)

    it('does not run the timer again afterwards', function()
      vim.fn.setreg('a', 'exit-secret')
      yank.schedule_auto_clear('a', 0.05, 'exit-secret')
      leave()
      vim.fn.setreg('a', 'exit-secret')

      vim.wait(200)

      assert.equals('exit-secret', vim.fn.getreg('a'))
      vim.fn.setreg('a', '')
    end)

    it('keeps the value out of ShaDa, so the next session never sees it', function()
      local shada = vim.fn.tempname()
      local function session(lua)
        return vim.fn.system({
          vim.v.progpath,
          '--headless',
          '-u',
          'NONE',
          '-i',
          shada,
          '--cmd',
          'set rtp^=' .. vim.fn.getcwd(),
          '-c',
          'lua ' .. lua,
          '-c',
          'qa!',
        })
      end

      session(
        "require('camouflage').setup({ project_config = { enabled = false } }) "
          .. "require('camouflage.yank').do_yank({ key = 'K', value = 'shada-secret' }, { register = 'a' })"
      )
      local next_session = session("io.stdout:write('a=' .. vim.fn.getreg('a'))")

      vim.fn.delete(shada)
      assert.equals('a=', next_session)
    end)
  end)

  describe('auto-clear with uppercase registers', function()
    local function yank_to(register)
      require('camouflage.config').get().yank.auto_clear_seconds = 0.05
      yank.do_yank({ key = 'TOKEN', value = 'upper-secret' }, { register = register })
    end

    it('restores the previous contents of the lowercase register', function()
      vim.fn.setreg('a', 'previous-')
      yank_to('A')
      assert.equals('previous-upper-secret', vim.fn.getreg('a'))

      vim.wait(400, function()
        return vim.fn.getreg('a') == 'previous-'
      end)
      assert.equals('previous-', vim.fn.getreg('a'))
    end)

    it('restores a linewise register with its type', function()
      vim.fn.setreg('a', { 'line one' }, 'l')
      yank_to('A')

      vim.wait(400, function()
        return not vim.fn.getreg('a'):find('upper-secret', 1, true)
      end)
      assert.equals('line one\n', vim.fn.getreg('a'))
      assert.equals('V', vim.fn.getregtype('a'))
    end)

    it('clears the register when it was empty before the yank', function()
      vim.fn.setreg('a', '')
      yank_to('A')

      vim.wait(400, function()
        return vim.fn.getreg('a') == ''
      end)
      assert.equals('', vim.fn.getreg('a'))
    end)

    it('leaves the register alone when the user replaced it', function()
      vim.fn.setreg('a', 'previous-')
      yank_to('A')
      vim.fn.setreg('a', 'user typed this')

      vim.wait(200)
      assert.equals('user typed this', vim.fn.getreg('a'))
    end)
  end)

  describe('register validation', function()
    it('rejects an invalid register without copying or throwing', function()
      vim.fn.setreg('z', 'original')

      local notify_called = false
      local notify_level = nil
      local original_notify = vim.notify
      vim.notify = function(_, level)
        notify_called = true
        notify_level = level
      end

      local ok, err = pcall(function()
        yank.do_yank({ key = 'A', value = 'secret' }, { register = '@bad' })
      end)
      vim.notify = original_notify
      if not ok then
        error(err, 0)
      end

      -- The default register is untouched and no error was raised.
      assert.equals('original', vim.fn.getreg('z'))
      assert.is_true(notify_called)
      assert.equals(vim.log.levels.ERROR, notify_level)
    end)
  end)
end)
