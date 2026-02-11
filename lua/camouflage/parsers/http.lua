---@mod camouflage.parsers.http HTTP parser
---@brief [[
--- Parser for .http files (REST client format).
--- Supports variable declarations: @variable_name = value
--- Reference: https://neovim.getkulala.net/docs/usage/http-file-spec/#variables
---@brief ]]

local M = {}

---@param content string
---@param bufnr number|nil Buffer number for TreeSitter parsing
---@return ParsedVariable[]
function M.parse(content, bufnr)
  -- Try TreeSitter first if buffer is provided
  if bufnr then
    local ts = require('camouflage.treesitter')
    local variables = ts.parse(bufnr, 'http', content)
    if variables then
      return variables
    end
  end

  -- Fallback to regex-based parsing
  return M.parse_regex(content)
end

---@param content string
---@return ParsedVariable[]
function M.parse_regex(content)
  local variables = {}
  local lines = vim.split(content, '\n', { plain = true })
  local current_index = 0

  for line_num, line in ipairs(lines) do
    local result = M.parse_line(line, line_num, current_index)
    if result then
      table.insert(variables, result)
    end
    current_index = current_index + #line + 1
  end

  return variables
end

---Parse a single line for variable declaration
---@param line string
---@param line_num number 1-indexed line number
---@param current_index number Byte offset where line starts
---@return ParsedVariable|nil
function M.parse_line(line, line_num, current_index)
  -- Pattern: @variable_name = value
  -- Variable names can contain letters, numbers, underscores, dots, hyphens, and $
  local key, value = line:match('^%s*@([A-Za-z_%.%$][A-Za-z0-9_%.%-%$]*)%s*=%s*(.+)$')

  if not key or not value then
    return nil
  end

  -- Trim trailing whitespace from value
  value = value:match('^(.-)%s*$')

  if not value or #value == 0 then
    return nil
  end

  -- Calculate value position
  local at_pos = line:find('@')
  local eq_pos = line:find('=', at_pos)
  if not eq_pos then
    return nil
  end

  local after_eq = line:sub(eq_pos + 1)
  local whitespace_before = #after_eq - #after_eq:gsub('^%s*', '')
  local value_start = current_index + eq_pos + whitespace_before
  local value_end = value_start + #value

  return {
    key = key,
    value = value,
    start_index = value_start,
    end_index = value_end,
    line_number = line_num - 1, -- 0-indexed
    is_nested = false,
    is_commented = false,
  }
end

return M
