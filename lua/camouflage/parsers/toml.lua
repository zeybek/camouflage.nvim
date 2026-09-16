---@mod camouflage.parsers.toml TOML parser

local M = {}

local config = require('camouflage.config')
local util = require('camouflage.parsers.util')

---@param content string
---@param bufnr number|nil Buffer number for TreeSitter parsing
---@return ParsedVariable[]
function M.parse(content, bufnr)
  -- Try TreeSitter first if buffer is provided
  if bufnr then
    local ts = require('camouflage.treesitter')
    local variables = ts.parse(bufnr, 'toml', content)
    if variables then
      return variables
    end
  end

  -- Fallback to regex-based parsing
  return M.parse_regex(content)
end

---@param content string
---@param lines? string[] Optional pre-split lines
---@return ParsedVariable[]
function M.parse_regex(content, lines)
  local variables = {}
  local cfg = config.get()
  local include_commented = cfg.parsers.include_commented or false

  lines = lines or vim.split(content, '\n', { plain = true })
  local current_section = ''
  local current_index = 0
  local offsets = nil
  -- 0-based offset of the end of an array value that started on an earlier line
  local skip_to = -1

  for line_num, line in ipairs(lines) do
    local line_start = current_index

    if line_start > skip_to then
      offsets = offsets or require('camouflage.offsets').from_content(content)
      local array_items, close_pos =
        M.parse_array(content, line, line_start, current_section, offsets)
      if array_items then
        vim.list_extend(variables, array_items)
        skip_to = close_pos - 1
      else
        local result =
          M.process_line(line, line_num, line_start, current_section, include_commented)

        if result then
          if result.type == 'section' then
            current_section = result.section
          elseif result.type == 'variable' then
            table.insert(variables, result.data)
          end
        end
      end
    end

    current_index = current_index + #line + 1
  end

  return variables
end

---Parse `key = [ ... ]`, which may span lines, into one variable per scalar
---item. Returns nil when the line doesn't start an array or it never closes.
---@param content string
---@param line string
---@param line_start number 0-based offset of the line
---@param current_section string
---@param offsets number[] Line start offsets of content
---@return ParsedVariable[]|nil variables
---@return number|nil close_pos 1-based position of the closing bracket
function M.parse_array(content, line, line_start, current_section, offsets)
  local key, bracket_col = line:match('^%s*([a-zA-Z_][a-zA-Z0-9_%.%-]*)%s*=%s*()%[')
  if not key then
    key, bracket_col = line:match('^%s*"([^"]+)"%s*=%s*()%[')
  end
  if not key then
    key, bracket_col = line:match("^%s*'([^']+)'%s*=%s*()%[")
  end
  if not key then
    return nil, nil
  end

  local items, close_pos = util.scan_array(content, line_start + bracket_col)
  if not close_pos then
    return nil, nil
  end

  local full_key = current_section ~= '' and (current_section .. '.' .. key) or key
  local variables = {}
  for _, item in ipairs(items) do
    local start_row = util.row_of(offsets, item.start_index)
    local end_row = util.row_of(offsets, math.max(item.start_index, item.end_index - 1))
    table.insert(variables, {
      key = full_key,
      value = item.value,
      start_index = item.start_index,
      end_index = item.end_index,
      line_number = start_row,
      is_nested = current_section ~= '' or key:find('%.') ~= nil,
      is_commented = false,
      is_multiline = end_row ~= start_row or nil,
    })
  end
  return variables, close_pos
end

---Process a single TOML line and determine its type
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
    -- Basic strings allow \" escapes; terminate on the first UNescaped quote so
    -- a value like "ab\"cd" is masked in full.
    local end_quote = util.find_unescaped(raw_value, '"', 2)
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

M.filetypes = { 'toml' }
M.file_patterns = { '*.toml' }
M.treesitter = { lang = 'toml' }

return M
