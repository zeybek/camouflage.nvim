---@mod camouflage.parsers.properties Properties parser

local M = {}

local config = require('camouflage.config')

---@param content string
---@param _bufnr number|nil Buffer number (unused, no TreeSitter support for .properties)
---@return ParsedVariable[]
function M.parse(content, _bufnr)
  local variables = {}
  local cfg = config.get()
  local include_commented = cfg.parsers.include_commented

  local lines = vim.split(content, '\n', { plain = true })
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

---Process a single properties line and determine its type
---@param line string The line content
---@param line_num number 1-indexed line number
---@param line_start number Byte offset where line starts
---@param current_section string Current section name
---@param include_commented boolean Whether to include commented lines
---@return table|nil Result with type and data, or nil
function M.process_line(line, line_num, line_start, current_section, include_commented)
  local trimmed = line:match('^%s*(.-)%s*$')

  if trimmed == '' then
    return nil
  end

  local is_commented = trimmed:match('^[#;]')
  if is_commented and not include_commented then
    return nil
  end

  local section = trimmed:match('^%[([^%]]+)%]$')
  if section then
    return { type = 'section', section = section }
  end

  local line_content = is_commented and trimmed:gsub('^[#;]%s*', '') or trimmed
  local key, sep, value = line_content:match('^([a-zA-Z0-9_%.%-]+)%s*([=:])%s*(.*)$')

  if not key or not value then
    return nil
  end

  local full_key = current_section ~= '' and (current_section .. '.' .. key) or key

  local sep_pos = line:find(sep, 1, true)
  if not sep_pos then
    return nil
  end

  local after_sep = line:sub(sep_pos + 1)
  local whitespace = #after_sep - #after_sep:gsub('^%s*', '')

  local value_start = line_start + sep_pos + whitespace
  local value_end = value_start + #value

  return {
    type = 'variable',
    data = {
      key = full_key,
      value = value,
      start_index = value_start,
      end_index = value_end,
      line_number = line_num - 1,
      is_nested = current_section ~= '' or key:find('%.'),
      is_commented = is_commented,
    },
  }
end

return M
