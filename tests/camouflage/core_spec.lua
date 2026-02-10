local core = require('camouflage.core')
local state = require('camouflage.state')
local config = require('camouflage.config')

describe('camouflage.core', function()
  before_each(function()
    config.setup()
    state.clear()
  end)

  describe('index_to_position', function()
    it('should convert index 0 to row 0, col 0', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      local pos = core.index_to_position(0, 0, lines)

      assert.is_not_nil(pos)
      assert.equals(0, pos.row)
      assert.equals(0, pos.col)
    end)

    it('should convert index within first line', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      local pos = core.index_to_position(0, 8, lines)

      assert.is_not_nil(pos)
      assert.equals(0, pos.row)
      assert.equals(8, pos.col)
    end)

    it('should convert index at end of first line', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      local pos = core.index_to_position(0, 14, lines)

      assert.is_not_nil(pos)
      assert.equals(0, pos.row)
      assert.equals(14, pos.col)
    end)

    it('should convert index at start of second line', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      -- First line is 14 chars, newline at 14, second line starts at 15
      local pos = core.index_to_position(0, 15, lines)

      assert.is_not_nil(pos)
      assert.equals(1, pos.row)
      assert.equals(0, pos.col)
    end)

    it('should convert index within second line', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      -- Second line starts at index 15, so 15+6=21 points to 'value'
      local pos = core.index_to_position(0, 21, lines)

      assert.is_not_nil(pos)
      assert.equals(1, pos.row)
      assert.equals(6, pos.col)
    end)

    it('should handle empty lines array', function()
      local lines = {}
      local pos = core.index_to_position(0, 5, lines)

      assert.is_nil(pos)
    end)

    it('should handle single character lines', function()
      local lines = { 'a', 'b', 'c' }
      local pos = core.index_to_position(0, 2, lines)

      assert.is_not_nil(pos)
      assert.equals(1, pos.row)
      assert.equals(0, pos.col)
    end)

    it('should clamp to last position for out of bounds index', function()
      local lines = { 'short' }
      local pos = core.index_to_position(0, 100, lines)

      assert.is_not_nil(pos)
      assert.equals(0, pos.row)
      assert.equals(5, pos.col)
    end)
  end)

  describe('clear_decorations', function()
    it('should clear namespace without errors', function()
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Should not throw
      assert.has_no.errors(function()
        core.clear_decorations(bufnr)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should use current buffer when bufnr not provided', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      assert.has_no.errors(function()
        core.clear_decorations()
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('is_masked', function()
    it('should return false when buffer has no state', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      assert.is_false(core.is_masked())

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should return true when buffer is masked', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      state.init_buffer(bufnr)

      assert.is_true(core.is_masked())

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should return false when buffer state is disabled', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      state.init_buffer(bufnr)
      state.update_buffer(bufnr, { enabled = false })

      assert.is_false(core.is_masked())

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('apply_decorations', function()
    it('should skip when disabled', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      config.set('enabled', false)

      assert.has_no.errors(function()
        core.apply_decorations(bufnr)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should skip files over max_lines', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      -- Create a buffer with many lines
      local lines = {}
      for i = 1, 100 do
        table.insert(lines, 'LINE_' .. i .. '=value' .. i)
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Set max_lines to a low value
      config.set('max_lines', 10)

      assert.has_no.errors(function()
        core.apply_decorations(bufnr)
      end)

      -- Should not have created any extmarks
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
      assert.equals(0, #extmarks)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should skip buffer without filename', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      -- Buffer has no name, should exit early
      assert.has_no.errors(function()
        core.apply_decorations(bufnr)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should skip unsupported file types', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, 'test.unsupported')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'some content' })
      vim.api.nvim_set_current_buf(bufnr)

      assert.has_no.errors(function()
        core.apply_decorations(bufnr)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('compute_line_offsets', function()
    it('should compute correct offsets for single line', function()
      local lines = { 'hello' }
      local offsets = core.compute_line_offsets(lines)

      assert.equals(0, offsets[1])
      assert.equals(6, offsets[2]) -- 5 chars + 1 newline
    end)

    it('should compute correct offsets for multiple lines', function()
      local lines = { 'line1', 'line2', 'line3' }
      local offsets = core.compute_line_offsets(lines)

      assert.equals(0, offsets[1])
      assert.equals(6, offsets[2])
      assert.equals(12, offsets[3])
      assert.equals(18, offsets[4])
    end)

    it('should handle empty lines', function()
      local lines = { '', 'text', '' }
      local offsets = core.compute_line_offsets(lines)

      assert.equals(0, offsets[1])
      assert.equals(1, offsets[2])
      assert.equals(6, offsets[3])
    end)
  end)

  describe('refresh', function()
    it('should not error when called', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      assert.has_no.errors(function()
        core.refresh()
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('refresh_all', function()
    it('should not error when called', function()
      assert.has_no.errors(function()
        core.refresh_all()
      end)
    end)
  end)
end)
