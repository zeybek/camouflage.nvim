---@mod camouflage.core Core decoration engine

local M = {}

local state = require('camouflage.state')
local config = require('camouflage.config')
local styles = require('camouflage.styles')
local parsers = require('camouflage.parsers')
local hooks = require('camouflage.hooks')

---Get the highlight group to use for masking
---@param cfg table Configuration
---@return string highlight group name
local function get_highlight_group(cfg)
  -- Use custom CamouflageMask if colors are configured
  if cfg.colors then
    return 'CamouflageMask'
  end
  return cfg.highlight_group
end

---Apply decorations to mask sensitive values in a buffer
---@param bufnr number Buffer number
---@param override_filename string|nil Optional filename for buffers without names (e.g., snacks preview)
function M.apply_decorations(bufnr, override_filename)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check is_enabled first to avoid unnecessary API calls
  if not config.is_enabled() then
    M.clear_decorations(bufnr)
    return
  end

  local cfg = config.get()
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if cfg.max_lines and line_count > cfg.max_lines then
    return
  end

  M.clear_decorations(bufnr)

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return
  end
  local content = table.concat(lines, '\n')

  local filename = override_filename or vim.api.nvim_buf_get_name(bufnr)
  if filename == '' then
    return
  end

  -- Find parser once and pass it to parse() to avoid redundant lookup
  local parser, parser_name = parsers.find_parser_for_file(filename)
  if not parser then
    return
  end

  -- HOOK: before_decorate
  local should_continue = hooks.emit('before_decorate', bufnr, filename)
  if should_continue == false then
    return
  end

  local variables = parsers.parse(filename, content, bufnr, parser, parser_name)
  if #variables == 0 then
    return
  end

  -- HOOK: variable_detected (filter variables)
  local filtered_variables = {}
  for _, var in ipairs(variables) do
    local should_mask = hooks.emit('variable_detected', bufnr, var)
    if should_mask ~= false then
      table.insert(filtered_variables, var)
    end
  end

  if #filtered_variables == 0 then
    return
  end

  state.set_variables(bufnr, filtered_variables)

  -- Pre-compute line offsets for O(1) index lookups
  local line_offsets = M.compute_line_offsets(lines)

  for _, var in ipairs(filtered_variables) do
    M.apply_single_decoration(bufnr, var, cfg, lines, line_offsets)
  end

  -- Disable wrap to prevent visual glitches with extmarks
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_set_option_value('wrap', false, { win = win })
    end
  end

  -- HOOK: after_decorate
  hooks.emit('after_decorate', bufnr, filtered_variables)
end

---@param bufnr number
---@param var table
---@param cfg table
---@param lines string[]
---@param line_offsets number[]|nil Pre-computed cumulative line offsets for O(1) lookup
function M.apply_single_decoration(bufnr, var, cfg, lines, line_offsets)
  if not var.value or var.value:match('^%s*$') then
    return
  end

  local start_pos = M.index_to_position(bufnr, var.start_index, lines, line_offsets)
  local end_pos = M.index_to_position(bufnr, var.end_index, lines, line_offsets)

  if not start_pos or not end_pos then
    return
  end

  local hl_group = get_highlight_group(cfg)

  -- Handle multiline values: apply extmark per line
  if var.is_multiline and start_pos.row ~= end_pos.row then
    M.apply_multiline_decoration(bufnr, var, cfg, lines, start_pos, end_pos, hl_group)
  else
    -- Single line value
    local masked_text = styles.generate_hidden_text(cfg.style, #var.value, var.value)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, state.namespace, start_pos.row, start_pos.col, {
      end_row = end_pos.row,
      end_col = end_pos.col,
      virt_text = { { masked_text, hl_group } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
      priority = 100,
    })
  end
end

---Apply decorations for multiline values (one extmark per line)
---@param bufnr number
---@param var table
---@param cfg table
---@param lines string[]
---@param start_pos {row: number, col: number}
---@param end_pos {row: number, col: number}
---@param hl_group string Highlight group to use
function M.apply_multiline_decoration(bufnr, var, cfg, lines, start_pos, end_pos, hl_group)
  for row = start_pos.row, end_pos.row do
    local line = lines[row + 1] -- lines is 1-indexed
    if not line then
      break
    end

    local col_start, col_end
    if row == start_pos.row then
      -- First line: from start_pos.col to end of line
      col_start = start_pos.col
      col_end = #line
    elseif row == end_pos.row then
      -- Last line: from start of content to end_pos.col
      col_start = line:match('^(%s*)'):len() -- Start after indentation
      col_end = end_pos.col
    else
      -- Middle lines: mask from indentation to end of line
      col_start = line:match('^(%s*)'):len()
      col_end = #line
    end

    -- Skip empty lines or lines with only whitespace
    local line_content = line:sub(col_start + 1, col_end)
    if line_content:match('^%s*$') then
      goto continue
    end

    local masked_text = styles.generate_hidden_text(cfg.style, col_end - col_start, line_content)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, state.namespace, row, col_start, {
      end_row = row,
      end_col = col_end,
      virt_text = { { masked_text, hl_group } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
      priority = 100,
    })

    ::continue::
  end
end

---@param bufnr number|nil
function M.clear_decorations(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.namespace, 0, -1)
end

---Compute cumulative line offsets for O(1) index-to-position lookup
---@param lines string[]
---@return number[] Cumulative byte offsets where each line starts
function M.compute_line_offsets(lines)
  local offsets = {}
  local current = 0
  for i, line in ipairs(lines) do
    offsets[i] = current
    current = current + #line + 1 -- +1 for newline
  end
  offsets[#lines + 1] = current -- sentinel for end of file
  return offsets
end

---Binary search to find the line containing the given byte index
---@param offsets number[]
---@param index number
---@return number row 1-based line number
local function binary_search_line(offsets, index)
  local lo, hi = 1, #offsets - 1
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if offsets[mid] <= index then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return lo
end

---@param bufnr number
---@param index number
---@param lines string[]|nil
---@param line_offsets number[]|nil Pre-computed offsets from compute_line_offsets
---@return {row: number, col: number}|nil
function M.index_to_position(bufnr, index, lines, line_offsets)
  if not lines then
    local ok
    ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
    if not ok then
      return nil
    end
  end

  if #lines == 0 then
    return nil
  end

  -- Use pre-computed offsets with binary search for O(log n) lookup
  if line_offsets then
    local row = binary_search_line(line_offsets, index)
    local col = index - line_offsets[row]
    -- Clamp to line length
    if col > #lines[row] then
      col = #lines[row]
    end
    return { row = row - 1, col = col }
  end

  -- Fallback: linear scan (for backward compatibility)
  local current = 0
  for row, line in ipairs(lines) do
    local line_end = current + #line
    if index <= line_end then
      return { row = row - 1, col = index - current }
    end
    current = line_end + 1
  end

  return { row = #lines - 1, col = #lines[#lines] }
end

function M.refresh()
  M.apply_decorations(vim.api.nvim_get_current_buf())
end

function M.refresh_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    local filename = vim.api.nvim_buf_get_name(bufnr)
    -- apply_decorations now handles parser lookup internally,
    -- but we still need is_supported check to avoid processing unsupported buffers
    if parsers.is_supported(filename) then
      M.apply_decorations(bufnr)
    end
  end
end

---@return boolean
function M.is_masked()
  return state.is_buffer_masked(vim.api.nvim_get_current_buf())
end

return M
