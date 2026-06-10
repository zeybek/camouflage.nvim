local position = require('camouflage.position')

describe('camouflage.position', function()
  local function setup_buf(lines, name)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_name(bufnr, name or ('/tmp/pos_' .. bufnr .. '.env'))
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  describe('compute_line_offsets', function()
    it('returns 0-based cumulative byte offsets with an end sentinel', function()
      local offsets = position.compute_line_offsets({ 'ab', 'cde' })
      assert.equals(0, offsets[1])
      assert.equals(3, offsets[2]) -- 'ab\n'
      assert.equals(7, offsets[3]) -- sentinel: + 'cde\n'
    end)
  end)

  describe('index_to_position', function()
    it('maps a buffer-global byte index to 0-based (row, col)', function()
      local lines = { 'API_KEY=secret', 'B=2' }
      local offsets = position.compute_line_offsets(lines)
      local pos = position.index_to_position(0, 15, lines, offsets) -- start of 'B=2' line
      assert.equals(1, pos.row)
      assert.equals(0, pos.col)
    end)
  end)

  describe('find_variable_at_cursor', function()
    it('returns the variable whose byte range contains the cursor', function()
      local bufnr = setup_buf({ 'API_KEY=secret123' })
      local vars = {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 17, line_number = 0 },
      }
      vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- inside the value
      local var = position.find_variable_at_cursor(bufnr, vars, {})
      assert.equals('API_KEY', var.key)
    end)

    it('strict mode returns nil when the cursor is not on a value', function()
      local bufnr = setup_buf({ 'API_KEY=secret123' })
      local vars = {
        { key = 'API_KEY', value = 'secret123', start_index = 8, end_index = 17, line_number = 0 },
      }
      vim.api.nvim_win_set_cursor(0, { 1, 2 }) -- on the key, not the value
      assert.is_nil(position.find_variable_at_cursor(bufnr, vars, { same_line_fallback = false }))
    end)

    it('lenient fallback picks the nearest variable by column on the row', function()
      local bufnr = setup_buf({ 'a=AAA b=BBB' })
      local vars = {
        { key = 'a', value = 'AAA', start_index = 2, end_index = 5, line_number = 0 },
        { key = 'b', value = 'BBB', start_index = 8, end_index = 11, line_number = 0 },
      }
      vim.api.nvim_win_set_cursor(0, { 1, 7 }) -- between values, closer to BBB
      local var = position.find_variable_at_cursor(bufnr, vars, { same_line_fallback = true })
      assert.equals('b', var.key)
    end)
  end)
end)
