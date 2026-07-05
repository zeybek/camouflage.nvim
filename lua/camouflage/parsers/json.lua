---@mod camouflage.parsers.json JSON parser

local M = {}

local config = require('camouflage.config')

---@param content string
---@param bufnr number|nil Buffer number for TreeSitter parsing
---@return ParsedVariable[]
function M.parse(content, bufnr)
  -- Try TreeSitter first if buffer is provided
  if bufnr then
    local ts = require('camouflage.treesitter')
    local variables = ts.parse(bufnr, 'json', content)
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
  local max_depth = config.get().parsers.json.max_depth or 10

  local ok = pcall(vim.json.decode, content)
  if ok then
    M.scan_valid_json(content, max_depth, variables)
  else
    M.parse_with_pattern(content, variables)
  end

  return variables
end

---Scan valid JSON in document order and emit supported object scalar values.
---Arrays and nulls are intentionally skipped to preserve the fallback contract.
---@param content string
---@param variables ParsedVariable[]
---@return nil
function M.scan_valid_json(content, max_depth, variables)
  local pos = M.skip_whitespace(content, 1)
  local char = content:sub(pos, pos)

  if char == '{' then
    M.scan_object(content, pos, {}, max_depth, variables)
  elseif char == '[' then
    M.skip_json_value(content, pos)
  end
end

---@param content string
---@param pos number
---@return number
function M.skip_whitespace(content, pos)
  local next_pos = content:find('%S', pos)
  return next_pos or (#content + 1)
end

---@param raw string
---@return string
function M.decode_json_string(raw)
  local ok, decoded = pcall(vim.json.decode, '"' .. raw .. '"')
  if ok and type(decoded) == 'string' then
    return decoded
  end
  return raw:gsub('\\"', '"'):gsub('\\\\', '\\')
end

---@param content string
---@param quote_pos number
---@return string|nil raw
---@return number|nil closing_quote
function M.parse_string_token(content, quote_pos)
  if content:sub(quote_pos, quote_pos) ~= '"' then
    return nil, nil
  end
  local closing_quote = M.find_closing_quote(content, quote_pos + 1)
  if not closing_quote then
    return nil, nil
  end
  return content:sub(quote_pos + 1, closing_quote - 1), closing_quote
end

---@param path string[]
---@param key string
---@return string[]
function M.path_with_key(path, key)
  local next_path = {}
  for i, part in ipairs(path) do
    next_path[i] = part
  end
  next_path[#next_path + 1] = key
  return next_path
end

---@param path string[]
---@param key string
---@return string
function M.full_key(path, key)
  if #path == 0 then
    return key
  end

  local parts = M.path_with_key(path, key)
  return table.concat(parts, '.')
end

---@param content string
---@param variables ParsedVariable[]
---@param path string[]
---@param key string|nil
---@param value string
---@param start_index number
---@param end_index number
---@param value_pos number 1-based value start for line number calculation
---@param max_depth number
---@return nil
function M.add_scalar_variable(
  content,
  variables,
  path,
  key,
  value,
  start_index,
  end_index,
  value_pos,
  max_depth
)
  if not key or #path > max_depth then
    return
  end
  if value == '' or value:match('^%s*$') then
    return
  end

  table.insert(variables, {
    key = M.full_key(path, key),
    value = value,
    start_index = start_index,
    end_index = end_index,
    line_number = M.get_line_number(content, value_pos),
    is_nested = #path > 0,
    is_commented = false,
  })
end

---@param content string
---@param pos number
---@param path string[]
---@param max_depth number
---@param variables ParsedVariable[]
---@return number
function M.scan_object(content, pos, path, max_depth, variables)
  pos = M.skip_whitespace(content, pos + 1)
  if content:sub(pos, pos) == '}' then
    return pos + 1
  end

  while pos <= #content do
    local raw_key, key_end = M.parse_string_token(content, pos)
    if not raw_key or not key_end then
      return pos + 1
    end

    local key = M.decode_json_string(raw_key)
    pos = M.skip_whitespace(content, key_end + 1)
    if content:sub(pos, pos) ~= ':' then
      return pos + 1
    end

    pos = M.scan_value(content, pos + 1, path, key, max_depth, variables)
    pos = M.skip_whitespace(content, pos)

    local char = content:sub(pos, pos)
    if char == ',' then
      pos = M.skip_whitespace(content, pos + 1)
    elseif char == '}' then
      return pos + 1
    else
      return pos + 1
    end
  end

  return pos
end

---@param content string
---@param pos number
---@param path string[]
---@param key string|nil
---@param max_depth number
---@param variables ParsedVariable[]
---@return number
function M.scan_value(content, pos, path, key, max_depth, variables)
  pos = M.skip_whitespace(content, pos)
  local char = content:sub(pos, pos)

  if char == '{' then
    local child_path = key and M.path_with_key(path, key) or path
    return M.scan_object(content, pos, child_path, max_depth, variables)
  elseif char == '[' then
    return M.skip_json_value(content, pos)
  elseif char == '"' then
    local raw_value, value_end = M.parse_string_token(content, pos)
    if not raw_value or not value_end then
      return pos + 1
    end
    M.add_scalar_variable(
      content,
      variables,
      path,
      key,
      raw_value,
      pos,
      value_end - 1,
      pos + 1,
      max_depth
    )
    return value_end + 1
  elseif content:sub(pos, pos + 3) == 'true' then
    M.add_scalar_variable(content, variables, path, key, 'true', pos - 1, pos + 3, pos, max_depth)
    return pos + 4
  elseif content:sub(pos, pos + 4) == 'false' then
    M.add_scalar_variable(content, variables, path, key, 'false', pos - 1, pos + 4, pos, max_depth)
    return pos + 5
  elseif content:sub(pos, pos + 3) == 'null' then
    return pos + 4
  end

  local raw_number, number_end = M.parse_number_literal(content, pos)
  if raw_number and number_end then
    M.add_scalar_variable(
      content,
      variables,
      path,
      key,
      raw_number,
      pos - 1,
      number_end,
      pos,
      max_depth
    )
    return number_end + 1
  end

  return pos + 1
end

---@param content string
---@param pos number
---@return string|nil raw_number
---@return number|nil end_pos
function M.parse_number_literal(content, pos)
  local len = #content
  local start_pos = pos

  if content:sub(pos, pos) == '-' then
    pos = pos + 1
  end

  local char = content:sub(pos, pos)
  if char == '0' then
    pos = pos + 1
  elseif char:match('[1-9]') then
    repeat
      pos = pos + 1
      char = content:sub(pos, pos)
    until pos > len or not char:match('%d')
  else
    return nil, nil
  end

  if content:sub(pos, pos) == '.' then
    pos = pos + 1
    if not content:sub(pos, pos):match('%d') then
      return nil, nil
    end
    repeat
      pos = pos + 1
      char = content:sub(pos, pos)
    until pos > len or not char:match('%d')
  end

  char = content:sub(pos, pos)
  if char == 'e' or char == 'E' then
    pos = pos + 1
    char = content:sub(pos, pos)
    if char == '+' or char == '-' then
      pos = pos + 1
    end
    if not content:sub(pos, pos):match('%d') then
      return nil, nil
    end
    repeat
      pos = pos + 1
      char = content:sub(pos, pos)
    until pos > len or not char:match('%d')
  end

  return content:sub(start_pos, pos - 1), pos - 1
end

---@param content string
---@param pos number
---@return number
function M.skip_json_value(content, pos)
  pos = M.skip_whitespace(content, pos)
  local char = content:sub(pos, pos)

  if char == '"' then
    local _, closing_quote = M.parse_string_token(content, pos)
    return closing_quote and (closing_quote + 1) or (#content + 1)
  elseif char == '{' then
    return M.skip_balanced(content, pos, '{', '}')
  elseif char == '[' then
    return M.skip_balanced(content, pos, '[', ']')
  elseif content:sub(pos, pos + 3) == 'true' or content:sub(pos, pos + 3) == 'null' then
    return pos + 4
  elseif content:sub(pos, pos + 4) == 'false' then
    return pos + 5
  end

  local _, number_end = M.parse_number_literal(content, pos)
  return number_end and (number_end + 1) or (pos + 1)
end

---@param content string
---@param pos number
---@param open_char string
---@param close_char string
---@return number
function M.skip_balanced(content, pos, open_char, close_char)
  local depth = 0

  while pos <= #content do
    local char = content:sub(pos, pos)
    if char == '"' then
      local _, closing_quote = M.parse_string_token(content, pos)
      pos = closing_quote and (closing_quote + 1) or (#content + 1)
    elseif char == open_char then
      depth = depth + 1
      pos = pos + 1
    elseif char == close_char then
      depth = depth - 1
      pos = pos + 1
      if depth == 0 then
        return pos
      end
    else
      pos = pos + 1
    end
  end

  return pos
end

---Find the closing quote, handling escaped quotes
---@param content string
---@param start_pos number Position after the opening quote
---@return number|nil Position of the closing quote
function M.find_closing_quote(content, start_pos)
  local pos = start_pos
  while pos <= #content do
    local char = content:sub(pos, pos)
    if char == '\\' then
      -- Skip escaped character
      pos = pos + 2
    elseif char == '"' then
      return pos
    else
      pos = pos + 1
    end
  end
  return nil
end

---@param content string
---@param variables ParsedVariable[]
function M.parse_with_pattern(content, variables)
  local current_pos = 1

  while current_pos <= #content do
    -- Find key pattern: "key":
    local key_start = content:find('"', current_pos)
    if not key_start then
      break
    end

    local key_end = M.find_closing_quote(content, key_start + 1)
    if not key_end then
      current_pos = key_start + 1
    else
      local key = content:sub(key_start + 1, key_end - 1)

      -- Find colon after key
      local after_key = content:sub(key_end + 1):match('^%s*:')
      if not after_key then
        current_pos = key_end + 1
      else
        local colon_pos = key_end + #content:sub(key_end + 1):match('^%s*')
        local value_search_start = colon_pos + 2

        -- Skip whitespace after colon
        local after_colon = content:sub(value_search_start)
        local whitespace = after_colon:match('^%s*')
        value_search_start = value_search_start + #whitespace

        -- Check if value is a string (starts with ")
        if content:sub(value_search_start, value_search_start) == '"' then
          local value_content_start = value_search_start + 1
          local value_end = M.find_closing_quote(content, value_content_start)
          if value_end then
            local value = content:sub(value_content_start, value_end - 1)
            -- Unescape the value for storage
            local unescaped_value = value:gsub('\\"', '"'):gsub('\\\\', '\\')
            table.insert(variables, {
              key = key,
              value = unescaped_value,
              start_index = value_content_start - 1,
              end_index = value_end - 1,
              line_number = M.get_line_number(content, value_content_start),
              is_nested = false,
              is_commented = false,
            })
            current_pos = value_end + 1
          else
            current_pos = value_search_start + 1
          end
        else
          current_pos = value_search_start + 1
        end
      end
    end
  end
end

---@param content string
---@param index number
---@return number
function M.get_line_number(content, index)
  local _, count = content:sub(1, index):gsub('\n', '')
  return count
end

M.filetypes = { 'json', 'jsonc' }
M.file_patterns = { '*.json' }
M.treesitter = { lang = 'json' }

return M
