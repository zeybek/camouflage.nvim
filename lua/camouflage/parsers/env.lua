---@mod camouflage.parsers.env ENV parser

local M = {}

local config = require('camouflage.config')

---@param content string
---@param _bufnr number|nil Buffer number (unused, no TreeSitter support for .env)
---@return ParsedVariable[]
function M.parse(content, _bufnr)
  local variables = {}
  local parser_config = config.get().parsers.env or {}
  ---@cast parser_config CamouflageEnvParserConfig
  local lines = vim.split(content, '\n', { plain = true })
  local current_index = 0

  local line_num = 1
  while line_num <= #lines do
    local line = lines[line_num]
    local result = M.parse_line(line, line_num, current_index, parser_config)
    local extra_lines = 0
    if result and not result.is_commented then
      extra_lines = M.extend_multiline(result, lines, line_num, current_index)
    end
    if result then
      table.insert(variables, result)
    end
    for i = line_num, line_num + extra_lines do
      current_index = current_index + #lines[i] + 1
    end
    line_num = line_num + extra_lines + 1
  end

  return variables
end

---Find the first unescaped `quote` in `text`, starting at `init`.
---@param text string
---@param quote string
---@param init number|nil
---@return number|nil
local function find_closing_quote(text, quote, init)
  local pos = init or 1
  while pos <= #text do
    local char = text:sub(pos, pos)
    if char == '\\' then
      pos = pos + 2
    elseif char == quote then
      return pos
    else
      pos = pos + 1
    end
  end
  return nil
end

---Extend a quoted value that is not closed on its own line over the following
---lines, as dotenv does (KEY="-----BEGIN ...<newline>...<newline>-----END ...").
---Updates `var` in place and returns how many extra lines the value consumed
---(0 when the quote closes on the first line or never closes).
---@param var ParsedVariable
---@param lines string[]
---@param line_num number 1-indexed line of the key
---@param line_start number Byte offset where that line starts
---@return number
function M.extend_multiline(var, lines, line_num, line_start)
  local line = lines[line_num]
  local quote_col = var.start_index - line_start + 1
  local quote = line:sub(quote_col, quote_col)
  if quote ~= '"' and quote ~= "'" and quote ~= '`' then
    return 0
  end

  local first_rest = line:sub(quote_col + 1)
  if find_closing_quote(first_rest, quote) then
    return 0
  end

  local offset = line_start + #line + 1
  for i = line_num + 1, #lines do
    local close = find_closing_quote(lines[i], quote)
    if close then
      local parts = { first_rest }
      for j = line_num + 1, i - 1 do
        table.insert(parts, lines[j])
      end
      table.insert(parts, lines[i]:sub(1, close - 1))

      var.value = table.concat(parts, '\n')
      var.start_index = var.start_index + 1
      var.end_index = offset + close - 1
      var.is_multiline = true
      return i - line_num
    end
    offset = offset + #lines[i] + 1
  end

  return 0
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

M.filetypes = { 'sh', 'bash', 'zsh' }
M.file_patterns = { '.env*', '*.env', '.envrc', '*.sh' }

return M
