---@mod camouflage.position Byte-offset / cursor position helpers
---@brief [[
--- Pure position math shared by the decoration engine, yank, and pwned.
--- The engine contract is "0-based byte offsets, end-exclusive, buffer-global":
--- parsers emit start_index/end_index as 0-based byte offsets into the
--- '\n'-joined buffer snapshot, and these helpers convert back to (row, col).
---
--- This is a leaf module: it depends only on camouflage.log and the Neovim
--- API, so core, yank, and pwned can all require it without import cycles.
---@brief ]]

local M = {}

local log = require('camouflage.log')

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

---Convert a buffer-global byte index to a 0-based (row, col) position
---@param bufnr number
---@param index number
---@param lines string[]|nil
---@param line_offsets number[]|nil Pre-computed offsets from compute_line_offsets
---@return {row: number, col: number}|nil
function M.index_to_position(bufnr, index, lines, line_offsets)
  if not lines then
    local ok, result = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
    if not ok then
      log.pcall_error('nvim_buf_get_lines', result, { bufnr = bufnr })
      return nil
    end
    lines = result
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

---Find the variable at the cursor position.
---
--- The cursor's line-local column is converted to a buffer-global byte offset
--- (the same convention parsers emit) before comparison, which is the bug the
--- pwned integration previously had: it compared a line-local column directly
--- against buffer-global start_index/end_index, so it never matched any
--- variable past the first line.
---@param bufnr number|nil Buffer number (default: current)
---@param variables ParsedVariable[]|nil Variables to search (caller supplies)
---@param opts {same_line_fallback: boolean}|nil
---  same_line_fallback=true also returns the first variable that merely shares
---  the cursor's row when no exact range match is found (lenient; used by yank).
---  Default false (strict; used by pwned so it never checks an off-cursor secret).
---@return ParsedVariable|nil
function M.find_variable_at_cursor(bufnr, variables, opts)
  opts = opts or {}
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not variables or #variables == 0 then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1] - 1 -- Convert to 0-indexed
  local cursor_col = cursor[2]

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    log.pcall_error('nvim_buf_get_lines', lines, { bufnr = bufnr })
    return nil
  end

  local line_offsets = M.compute_line_offsets(lines)
  local line_start = line_offsets[cursor_row + 1]
  if not line_start then
    return nil
  end
  local cursor_byte = line_start + cursor_col

  -- First pass: exact match (cursor within value byte range)
  for _, var in ipairs(variables) do
    if cursor_byte >= var.start_index and cursor_byte < var.end_index then
      return var
    end
  end

  -- Second pass: same-line match (lenient, opt-in). Pick the variable on the
  -- cursor's row whose value byte-range is nearest the cursor, so a line with
  -- several secrets (e.g. user + password) yanks the closest one, not the first.
  if opts.same_line_fallback then
    local best, best_dist
    for _, var in ipairs(variables) do
      local var_pos = M.index_to_position(bufnr, var.start_index, lines, line_offsets)
      if var_pos and var_pos.row == cursor_row then
        local dist
        if cursor_byte < var.start_index then
          dist = var.start_index - cursor_byte
        elseif cursor_byte >= var.end_index then
          dist = cursor_byte - (var.end_index - 1)
        else
          dist = 0
        end
        if not best_dist or dist < best_dist then
          best, best_dist = var, dist
        end
      end
    end
    return best
  end

  return nil
end

return M
