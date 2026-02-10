---@mod camouflage.parsers.toml TOML parser

local M = {}

---@param content string
---@param lines? string[] Optional pre-split lines
---@return ParsedVariable[]
function M.parse(content, lines)
  local variables = {}
  local config = require('camouflage.config').get()
  local include_commented = config.parsers.include_commented

  lines = lines or vim.split(content, '\n', { plain = true })
  local current_section = ''
  local current_index = 0

  for line_num, line in ipairs(lines) do
    local line_start = current_index
    local result = M.process_line(line, line_num, line_start, current_section, include_commented)

    if result then
      if result.type == 'section' then
        current_section = result.section
      elseif result.type == 'variable' then
        table.insert(variables, result.data)
      end
    end

    current_index = current_index + #line + 1
  end

  return variables
end

---@return table|nil
function M.process_line(line, line_num, line_start, current_section, include_commented)
  local trimmed = line:match('^%s*(.-)%s*$')

  if trimmed == '' then
    return nil
  end

  local is_commented = trimmed:match('^#')
  if is_commented and not include_commented then
    return nil
  end

  local section = trimmed:match('^%[([^%]]+)%]$')
  if section then
    return { type = 'section', section = section }
  end

  local array_section = trimmed:match('^%[%[([^%]]+)%]%]$')
  if array_section then
    return { type = 'section', section = array_section }
  end

  local line_content = is_commented and trimmed:gsub('^#%s*', '') or trimmed
  local parsed = M.parse_key_value(line_content, line, line_start)

  if not parsed then
    return nil
  end

  local full_key = current_section ~= '' and (current_section .. '.' .. parsed.key) or parsed.key

  return {
    type = 'variable',
    data = {
      key = full_key,
      value = parsed.value,
      start_index = parsed.value_start,
      end_index = parsed.value_end,
      line_number = line_num - 1,
      is_nested = current_section ~= '' or parsed.key:find('%.'),
      is_commented = is_commented,
    },
  }
end

---@param trimmed_line string
---@param original_line string
---@param line_start number
---@return {key: string, value: string, value_start: number, value_end: number}|nil
function M.parse_key_value(trimmed_line, original_line, line_start)
  local key, raw_value = trimmed_line:match('^([a-zA-Z_][a-zA-Z0-9_%.%-]*)%s*=%s*(.+)$')

  if not key then
    key, raw_value = trimmed_line:match('^"([^"]+)"%s*=%s*(.+)$')
  end
  if not key then
    key, raw_value = trimmed_line:match("^'([^']+)'%s*=%s*(.+)$")
  end

  if not key or not raw_value then
    return nil
  end

  local value, quote_offset = M.parse_value(raw_value)

  local eq_pos = original_line:find('=')
  if not eq_pos then
    return nil
  end

  local after_eq = original_line:sub(eq_pos + 1)
  local whitespace = #after_eq - #after_eq:gsub('^%s*', '')

  local value_start = line_start + eq_pos + whitespace + quote_offset
  local value_end = value_start + #value

  return {
    key = key,
    value = value,
    value_start = value_start,
    value_end = value_end,
  }
end

---@param raw_value string
---@return string value, number quote_offset
function M.parse_value(raw_value)
  if raw_value:match('^"') and not raw_value:match('^"""') then
    local end_quote = raw_value:find('"', 2)
    if end_quote then
      return raw_value:sub(2, end_quote - 1), 1
    end
  end

  if raw_value:match("^'") and not raw_value:match("^'''") then
    local end_quote = raw_value:find("'", 2)
    if end_quote then
      return raw_value:sub(2, end_quote - 1), 1
    end
  end

  if raw_value:match('^"""') then
    local end_quote = raw_value:find('"""', 4)
    if end_quote then
      return raw_value:sub(4, end_quote - 1), 3
    end
  end

  if raw_value:match("^'''") then
    local end_quote = raw_value:find("'''", 4)
    if end_quote then
      return raw_value:sub(4, end_quote - 1), 3
    end
  end

  local comment_pos = raw_value:find('#')
  if comment_pos then
    raw_value = raw_value:sub(1, comment_pos - 1):match('^%s*(.-)%s*$')
  end

  return raw_value, 0
end

return M
