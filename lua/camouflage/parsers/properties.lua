---@mod camouflage.parsers.properties Properties parser

local M = {}

local config = require('camouflage.config')

---java.util.Properties syntax (whitespace separators, `!` comments, logical
---lines) only applies to .properties files; .ini and .conf use the plain
---`key = value` / `key: value` rules.
---@param bufnr number|nil
---@param filename string|nil
---@return boolean
local function is_java_properties(bufnr, filename)
  if not filename and bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    filename = vim.api.nvim_buf_get_name(bufnr)
  end
  return filename ~= nil and filename:match('%.properties$') ~= nil
end

---@param content string
---@param bufnr number|nil Buffer number (no TreeSitter support for .properties)
---@param filename string|nil File name, decides whether Java properties rules apply
---@return ParsedVariable[]
function M.parse(content, bufnr, filename)
  local variables = {}
  local cfg = config.get()
  local include_commented = cfg.parsers.include_commented or false
  local java = is_java_properties(bufnr, filename)

  local lines = vim.split(content, '\n', { plain = true })
  local current_section = ''
  local current_index = 0
  -- Variable whose value continues on the next line (Java logical lines)
  local continued = nil ---@type ParsedVariable|nil

  for line_num, line in ipairs(lines) do
    local line_start = current_index

    if continued then
      -- Leading whitespace of a continuation line is not part of the value.
      local col, text = line:match('^%s*()(.-)%s*$')
      local piece = M.ends_with_continuation(text) and text:sub(1, -2) or text
      if piece ~= '' then
        continued.value = continued.value .. piece
        continued.end_index = line_start + col - 1 + #piece
        continued.is_multiline = true
      end
      if not M.ends_with_continuation(text) then
        continued = nil
      end
    else
      local result =
        M.process_line(line, line_num, line_start, current_section, include_commented, java)

      if result then
        if result.type == 'section' then
          current_section = result.section
        elseif result.type == 'variable' then
          table.insert(variables, result.data)
          if java and not result.data.is_commented and M.ends_with_continuation(line) then
            local data = result.data
            data.value = data.value:sub(1, -2)
            data.end_index = data.start_index + #data.value
            continued = data
          end
        end
      end
    end

    current_index = current_index + #line + 1
  end

  return variables
end

---A logical line continues when it ends with an odd number of backslashes.
---@param line string
---@return boolean
function M.ends_with_continuation(line)
  local slashes = line:match('(\\*)%s*$') or ''
  return #slashes % 2 == 1
end

---Split `key<separator>value`. Backslash escapes a character in the key
---(`\:`, `\=`, `\ `). With `allow_space`, whitespace alone also separates,
---like java.util.Properties.
---@param s string Line content without leading whitespace
---@param allow_space boolean
---@return string|nil key Key with escapes removed
---@return number|nil value_col 1-based column where the value starts
function M.split_key_value(s, allow_space)
  local i = 1
  while i <= #s do
    local char = s:sub(i, i)
    if char == '\\' then
      i = i + 2
    elseif char == '=' or char == ':' or char:match('%s') then
      break
    else
      i = i + 1
    end
  end

  local raw_key = s:sub(1, i - 1)
  if raw_key == '' or i > #s then
    return nil, nil
  end

  local sep_col = s:match('^%s*()', i)
  local sep = s:sub(sep_col, sep_col)
  local value_col
  if sep == '=' or sep == ':' then
    value_col = s:match('^%s*()', sep_col + 1)
  elseif allow_space and sep_col > i then
    value_col = sep_col
  else
    return nil, nil
  end

  return (raw_key:gsub('\\(.)', '%1')), value_col
end

---Process a single properties line and determine its type
---@param line string The line content
---@param line_num number 1-indexed line number
---@param line_start number Byte offset where line starts
---@param current_section string Current section name
---@param include_commented boolean Whether to include commented lines
---@return table|nil Result with type and data, or nil
function M.process_line(line, line_num, line_start, current_section, include_commented, java)
  local trimmed = line:match('^%s*(.-)%s*$')

  if trimmed == '' then
    return nil
  end

  local is_commented = trimmed:match(java and '^[#!]' or '^[#;]')
  if is_commented and not include_commented then
    return nil
  end

  local section = trimmed:match('^%[([^%]]+)%]$')
  if section then
    return { type = 'section', section = section }
  end

  local line_content = is_commented and trimmed:gsub('^[#;!]%s*', '') or trimmed
  local key, value_col = M.split_key_value(line_content, java == true)
  if not key then
    return nil
  end
  if not java and not key:match('^[a-zA-Z0-9_%.%-]+$') then
    -- .ini/.conf keep the old, stricter key shape
    return nil
  end
  local value = line_content:sub(value_col)

  local full_key = current_section ~= '' and (current_section .. '.' .. key) or key

  -- line_content is the trimmed line (minus a comment marker), so it occurs in
  -- the original line and gives the value's column there.
  local content_col = line:find(line_content, 1, true)
  if not content_col then
    return nil
  end

  local value_start = line_start + (content_col - 1) + (value_col - 1)
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

M.filetypes = { 'properties', 'dosini', 'config' }
M.file_patterns = { '*.properties', '*.ini', '*.conf', 'credentials' }

return M
