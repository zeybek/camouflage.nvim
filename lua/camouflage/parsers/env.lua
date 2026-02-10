---@mod camouflage.parsers.env ENV parser

local M = {}

---@param content string
---@param lines? string[] Optional pre-split lines
---@return ParsedVariable[]
function M.parse(content, lines)
  local variables = {}
  local parser_config = require('camouflage.config').get().parsers.env
  lines = lines or vim.split(content, '\n', { plain = true })
  local current_index = 0

  for line_num, line in ipairs(lines) do
    local result = M.parse_line(line, line_num, current_index, parser_config)
    if result then
      table.insert(variables, result)
    end
    current_index = current_index + #line + 1
  end

  return variables
end

---@param line string
---@param line_num number
---@param current_index number
---@param parser_config table
---@return table|nil
function M.parse_line(line, line_num, current_index, parser_config)
  local is_commented = false
  local parse_line = line

  if line:match('^%s*#') then
    is_commented = true
    if not parser_config.include_commented then
      return nil
    end
    parse_line = line:gsub('^%s*#%s*', '')
  end

  local key, value
  if parser_config.include_export then
    key, value = parse_line:match('^%s*export%s+([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.*)$')
  end
  if not key then
    key, value = parse_line:match('^%s*([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.*)$')
  end

  if not key or not value then
    return nil
  end

  local trimmed_value = value:match('^%s*(.-)%s*$')
  if not trimmed_value or #trimmed_value == 0 then
    return nil
  end

  local unquoted_value = trimmed_value
  local quote_offset = 0

  if trimmed_value:match('^".*"$') then
    unquoted_value = trimmed_value:sub(2, -2)
    quote_offset = 1
  elseif trimmed_value:match("^'.*'$") then
    unquoted_value = trimmed_value:sub(2, -2)
    quote_offset = 1
  end

  local eq_pos = line:find('=')
  if not eq_pos then
    return nil
  end

  local after_eq = line:sub(eq_pos + 1)
  local whitespace_before = #after_eq - #after_eq:gsub('^%s*', '')
  local value_start = current_index + eq_pos + whitespace_before + quote_offset
  local value_end = value_start + #unquoted_value

  return {
    key = key,
    value = unquoted_value,
    start_index = value_start,
    end_index = value_end,
    line_number = line_num - 1,
    is_nested = false,
    is_commented = is_commented,
  }
end

return M
