-- End-to-end placement test: after apply_decorations, the overlay extmarks must
-- cover exactly each value's byte range. This exercises the full pipeline
-- (parser -> state -> core.index_to_position -> set_extmark) and would catch a
-- coordinate regression in core, not just in a parser.

local core = require('camouflage.core')
local state = require('camouflage.state')
local config = require('camouflage.config')

describe('camouflage end-to-end extmark placement', function()
  before_each(function()
    -- Full setup so the parser registry (M.parsers) is populated; this spec
    -- drives the whole apply_decorations -> find_parser_for_file path, unlike
    -- the unit parser specs that call parser.parse() directly.
    require('camouflage').setup()
  end)

  -- 0-based (row, col) of a buffer-global byte offset, computed independently
  -- of core so a drift in core.index_to_position is caught here.
  local function pos_of(content, byte_index)
    local row, line_start = 0, 0
    for i = 0, byte_index - 1 do
      if content:sub(i + 1, i + 1) == '\n' then
        row = row + 1
        line_start = i + 1
      end
    end
    return row, byte_index - line_start
  end

  it('places overlay extmarks exactly on each value range', function()
    local lines = { 'API_KEY=secret123', 'DB_PASSWORD=hunter2' }
    local content = table.concat(lines, '\n')

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, '/tmp/camouflage_test/app.env')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    core.apply_decorations(bufnr)

    local variables = state.get_variables(bufnr)
    assert.is_true(#variables >= 2, 'expected the env parser to find both values')

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, { details = true })
    assert.is_true(#marks >= 2, 'expected an extmark per value')

    for _, var in ipairs(variables) do
      local srow, scol = pos_of(content, var.start_index)
      local erow, ecol = pos_of(content, var.end_index)
      local found = false
      for _, m in ipairs(marks) do
        if m[2] == srow and m[3] == scol then
          found = true
          assert.equals(erow, m[4].end_row)
          assert.equals(ecol, m[4].end_col)
        end
      end
      assert.is_true(
        found,
        string.format('no extmark at expected (%d, %d) for key %s', srow, scol, var.key)
      )
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('disables wrap while masked and restores it when masking stops', function()
    require('camouflage').setup()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(bufnr, '/tmp/camouflage_test/wrap.env')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'API_KEY=secret123' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.wo.wrap = true

    core.apply_decorations(bufnr)
    assert.is_false(vim.wo.wrap)

    -- Stop masking for this buffer; the original wrap value is restored.
    config.setup({ enabled = false })
    core.apply_decorations(bufnr)
    assert.is_true(vim.wo.wrap)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('respects the vim.b.camouflage_enabled buffer-local override', function()
    require('camouflage').setup()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, '/tmp/camouflage_test/blocal.env')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'API_KEY=secret123' })
    vim.b[bufnr].camouflage_enabled = false

    core.apply_decorations(bufnr)

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
    assert.equals(0, #marks)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('does not leave stale extmarks or variables when a buffer grows past max_lines', function()
    config.setup({ max_lines = 3 })
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, '/tmp/camouflage_test/grow.env')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'API_KEY=secret123' })

    core.apply_decorations(bufnr)
    assert.is_true(#state.get_variables(bufnr) >= 1)

    -- Grow past max_lines: decorations and stored variables must be cleared,
    -- not left drifting.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'a=1', 'b=2', 'c=3', 'd=4', 'e=5' })
    core.apply_decorations(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
    assert.equals(0, #marks)
    assert.equals(0, #state.get_variables(bufnr))
    assert.is_false(state.is_buffer_masked(bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
