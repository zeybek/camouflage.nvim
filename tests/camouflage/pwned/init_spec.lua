-- Pwned feature requires Neovim 0.10+ (vim.system)
if vim.fn.has('nvim-0.10') == 0 then
  describe('camouflage.pwned (skipped)', function()
    it('requires Neovim 0.10+', function()
      pending('Pwned feature requires Neovim 0.10+')
    end)
  end)
  return
end

describe('camouflage.pwned', function()
  local pwned
  local test_counter = 0

  local function with_system_unavailable(fn)
    local original_system = vim.system
    vim.system = nil
    local ok, err = pcall(fn)
    vim.system = original_system
    if not ok then
      error(err, 0)
    end
  end

  before_each(function()
    pwned = require('camouflage.pwned')
  end)

  local function setup_test_buffer(content, filename)
    test_counter = test_counter + 1
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, '\n'))
    vim.api.nvim_buf_set_name(bufnr, (filename or '/tmp/pwned.env') .. '.' .. test_counter)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  describe('setup', function()
    it('should not error', function()
      assert.has_no.errors(function()
        pwned.setup()
      end)
    end)
  end)

  describe('is_available', function()
    it('should return boolean', function()
      local result = pwned.is_available()
      assert.is_boolean(result)
    end)

    it('should return true when dependencies are met', function()
      -- Hashing is in-process; network checks need curl and vim.system.
      assert.is_true(pwned.is_available())
    end)

    it('returns false when vim.system is unavailable', function()
      with_system_unavailable(function()
        assert.is_false(pwned.is_available())
      end)
    end)
  end)

  describe('unavailable runtime', function()
    it('public check entrypoints exit through callbacks without throwing', function()
      with_system_unavailable(function()
        local current_result = 'unset'
        local line_result = 'unset'
        local buffer_result = 'unset'

        assert.has_no.errors(function()
          pwned.check_current(function(result)
            current_result = result
          end)
          pwned.check_line(function(results)
            line_result = results
          end)
          pwned.check_buffer(function(results)
            buffer_result = results
          end)
        end)

        assert.is_nil(current_result)
        assert.same({}, line_result)
        assert.same({}, buffer_result)
      end)
    end)
  end)

  describe('clear', function()
    it('should not error on empty buffer', function()
      assert.has_no.errors(function()
        pwned.clear()
      end)
    end)
  end)

  describe('clear_cache', function()
    it('should clear the cache', function()
      local cache = require('camouflage.pwned.cache')
      cache.set('TEST', { pwned = true, count = 1 })
      pwned.clear_cache()
      assert.is_nil(cache.get('TEST'))
    end)
  end)

  describe('check_current', function()
    it('does not check a variable when the cursor is at its end-exclusive boundary', function()
      local pwned_check = require('camouflage.pwned.check')
      local state = require('camouflage.state')
      local original_is_available = pwned_check.is_available
      local original_check_variable = pwned_check.check_variable
      local original_notify = vim.notify

      local ok, err = pcall(function()
        local bufnr = setup_test_buffer('PASSWORD=secret,', '/tmp/pwned.env')
        state.set_variables(bufnr, {
          { key = 'PASSWORD', value = 'secret', start_index = 9, end_index = 15, line_number = 0 },
        })
        vim.api.nvim_win_set_cursor(0, { 1, 15 }) -- comma after the value

        local checked = false
        pwned_check.is_available = function()
          return true
        end
        pwned_check.check_variable = function()
          checked = true
        end
        vim.notify = function() end

        local callback_result = 'unset'
        pwned.check_current(function(result)
          callback_result = result
        end)

        assert.is_false(checked)
        assert.is_nil(callback_result)
      end)

      pwned_check.is_available = original_is_available
      pwned_check.check_variable = original_check_variable
      vim.notify = original_notify

      if not ok then
        error(err, 0)
      end
    end)
  end)

  describe('API exposure', function()
    it('should expose check_current function', function()
      assert.is_function(pwned.check_current)
    end)

    it('should expose check_line function', function()
      assert.is_function(pwned.check_line)
    end)

    it('should expose check_buffer function', function()
      assert.is_function(pwned.check_buffer)
    end)

    it('should expose on_text_changed function', function()
      assert.is_function(pwned.on_text_changed)
    end)

    it('should expose on_buf_enter function', function()
      assert.is_function(pwned.on_buf_enter)
    end)

    it('should expose on_buf_write function', function()
      assert.is_function(pwned.on_buf_write)
    end)
  end)

  describe('on_text_changed', function()
    it('should not error on empty buffer', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      assert.has_no.errors(function()
        pwned.on_text_changed(bufnr)
      end)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should not error on unsupported file type', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, 'test.txt')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'some content' })
      vim.api.nvim_set_current_buf(bufnr)
      assert.has_no.errors(function()
        pwned.on_text_changed(bufnr)
      end)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should not error on supported file with variables', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, '.env')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'PASSWORD=secret123' })
      vim.api.nvim_set_current_buf(bufnr)
      assert.has_no.errors(function()
        pwned.on_text_changed(bufnr)
      end)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('on_buf_enter', function()
    it('should not error on empty buffer', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.has_no.errors(function()
        pwned.on_buf_enter(bufnr)
      end)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('on_buf_write', function()
    it('should not error on empty buffer', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.has_no.errors(function()
        pwned.on_buf_write(bufnr)
      end)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('independent operation', function()
    it('should work when camouflage state is empty', function()
      -- Create a buffer with env content but don't initialize camouflage state
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, '.env')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'API_KEY=test123' })
      vim.api.nvim_set_current_buf(bufnr)

      -- Ensure state is empty for this buffer
      local state = require('camouflage.state')
      state.remove_buffer(bufnr)

      -- on_text_changed should still work (parse independently)
      assert.has_no.errors(function()
        pwned.on_text_changed(bufnr)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should parse file when camouflage is disabled', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, '.env')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'SECRET=password123' })
      vim.api.nvim_set_current_buf(bufnr)

      -- Clear any existing state
      local state = require('camouflage.state')
      state.remove_buffer(bufnr)

      -- Disable camouflage globally
      local config = require('camouflage.config')
      local original_enabled = config.get().enabled
      config.set('enabled', false)

      -- Pwned should still work
      assert.has_no.errors(function()
        pwned.on_buf_enter(bufnr)
        pwned.on_buf_write(bufnr)
        pwned.on_text_changed(bufnr)
      end)

      -- Restore original state
      config.set('enabled', original_enabled)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
