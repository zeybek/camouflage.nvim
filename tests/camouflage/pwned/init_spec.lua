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

  before_each(function()
    pwned = require('camouflage.pwned')
  end)

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
      -- On most systems with curl and sha1sum
      assert.is_true(pwned.is_available())
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
