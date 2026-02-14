---@mod camouflage.parsers.dockerfile Dockerfile parser

local M = {}

local config = require('camouflage.config')

---@param content string
---@param bufnr number|nil Buffer number for TreeSitter parsing
---@return ParsedVariable[]
function M.parse(content, bufnr)
  -- Try TreeSitter first if buffer is provided
  if bufnr then
    local ts = require('camouflage.treesitter')
    local variables = ts.parse(bufnr, 'dockerfile', content)
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
  local cfg = config.get()
  local include_commented = cfg.parsers.include_commented or false

  local lines = vim.split(content, '\n', { plain = true })
  local current_index = 0

  for line_num, line in ipairs(lines) do
    local line_start = current_index

    local results = M.process_line(line, line_num, line_start, include_commented)
    if results then
      for _, result in ipairs(results) do
        table.insert(variables, result)
      end
    end

    current_index = current_index + #line + 1
  end

  return variables
end

---Process a single Dockerfile line
---@param line string The line content
---@param line_num number 1-indexed line number
---@param line_start number Byte offset where line starts
---@param include_commented boolean Whether to include commented lines
---@return table[]|nil List of parsed variables or nil
function M.process_line(line, line_num, line_start, include_commented)
  local trimmed = line:match('^%s*(.-)%s*$')
  if trimmed == '' then
    return nil
  end

  -- Check for comments
  local is_commented = line:match('^%s*#') ~= nil
  if is_commented then
    if not include_commented then
      return nil
    end
    -- Remove comment prefix for parsing
    trimmed = line:gsub('^%s*#%s*', '')
  end

  local results = {}

  -- Try ENV instruction
  local env_results = M.parse_env(line, trimmed, line_num, line_start, is_commented)
  if env_results then
    for _, r in ipairs(env_results) do
      table.insert(results, r)
    end
  end

  -- Try ARG instruction
  local arg_result = M.parse_arg(line, trimmed, line_num, line_start, is_commented)
  if arg_result then
    table.insert(results, arg_result)
  end

  -- Try LABEL instruction
  local label_results = M.parse_label(line, trimmed, line_num, line_start, is_commented)
  if label_results then
    for _, r in ipairs(label_results) do
      table.insert(results, r)
    end
  end

  if #results > 0 then
    return results
  end
  return nil
end

---Parse ENV instruction
---Supports: ENV KEY=value, ENV KEY="value", ENV KEY value (legacy)
---@param original_line string Original line for position calculation
---@param trimmed string Trimmed line content
---@param line_num number 1-indexed line number
---@param line_start number Byte offset where line starts
---@param is_commented boolean Whether this is a commented line
---@return table[]|nil
function M.parse_env(original_line, trimmed, line_num, line_start, is_commented)
  -- Check if line starts with ENV (case insensitive)
  if not trimmed:match('^[eE][nN][vV]%s') then
    return nil
  end

  local results = {}
  local after_env = trimmed:match('^[eE][nN][vV]%s+(.+)$')
  if not after_env then
    return nil
  end

  -- Parse KEY=value pairs using custom parser for quoted strings
  local pairs = M.parse_key_value_pairs(after_env)
  for _, pair in ipairs(pairs) do
    local pos = M.find_value_position(original_line, pair.key .. '=', pair.raw_value, line_start)
    if pos then
      table.insert(results, {
        key = pair.key,
        value = pair.value,
        start_index = pos.start + pair.quote_offset,
        end_index = pos.start + pair.quote_offset + #pair.value,
        line_number = line_num - 1,
        is_nested = false,
        is_commented = is_commented,
      })
    end
  end

  -- Try legacy format: ENV KEY value (single pair, space separated)
  if #results == 0 then
    local key, value = after_env:match('^([A-Za-z_][A-Za-z0-9_]*)%s+(.+)$')
    if key and value and not value:match('=') then
      local unquoted, quote_offset = M.unquote(value)
      local pos = M.find_value_position(original_line, key, value, line_start)
      if pos then
        table.insert(results, {
          key = key,
          value = unquoted,
          start_index = pos.start + quote_offset,
          end_index = pos.start + quote_offset + #unquoted,
          line_number = line_num - 1,
          is_nested = false,
          is_commented = is_commented,
        })
      end
    end
  end

  if #results > 0 then
    return results
  end
  return nil
end

---Parse ARG instruction
---Supports: ARG KEY=value (skips ARG KEY without value)
---@param original_line string Original line for position calculation
---@param trimmed string Trimmed line content
---@param line_num number 1-indexed line number
---@param line_start number Byte offset where line starts
---@param is_commented boolean Whether this is a commented line
---@return table|nil
function M.parse_arg(original_line, trimmed, line_num, line_start, is_commented)
  -- Check if line starts with ARG (case insensitive)
  if not trimmed:match('^[aA][rR][gG]%s') then
    return nil
  end

  local after_arg = trimmed:match('^[aA][rR][gG]%s+(.+)$')
  if not after_arg then
    return nil
  end

  -- ARG KEY=value format
  local key, value = after_arg:match('^([A-Za-z_][A-Za-z0-9_]*)=(.+)$')
  if not key or not value then
    -- ARG KEY without default value - skip
    return nil
  end

  local unquoted, quote_offset = M.unquote(value)
  local pos = M.find_value_position(original_line, key .. '=', value, line_start)
  if pos then
    return {
      key = key,
      value = unquoted,
      start_index = pos.start + quote_offset,
      end_index = pos.start + quote_offset + #unquoted,
      line_number = line_num - 1,
      is_nested = false,
      is_commented = is_commented,
    }
  end
  return nil
end

---Parse LABEL instruction
---Supports: LABEL key=value key2=value2
---@param original_line string Original line for position calculation
---@param trimmed string Trimmed line content
---@param line_num number 1-indexed line number
---@param line_start number Byte offset where line starts
---@param is_commented boolean Whether this is a commented line
---@return table[]|nil
function M.parse_label(original_line, trimmed, line_num, line_start, is_commented)
  -- Check if line starts with LABEL (case insensitive)
  if not trimmed:match('^[lL][aA][bB][eE][lL]%s') then
    return nil
  end

  local results = {}
  local after_label = trimmed:match('^[lL][aA][bB][eE][lL]%s+(.+)$')
  if not after_label then
    return nil
  end

  -- Parse key=value pairs using custom parser for quoted strings
  -- LABEL keys can contain dots and hyphens
  local pairs = M.parse_key_value_pairs(after_label, true)
  for _, pair in ipairs(pairs) do
    local pos = M.find_value_position(original_line, pair.key .. '=', pair.raw_value, line_start)
    if pos then
      table.insert(results, {
        key = pair.key,
        value = pair.value,
        start_index = pos.start + pair.quote_offset,
        end_index = pos.start + pair.quote_offset + #pair.value,
        line_number = line_num - 1,
        is_nested = false,
        is_commented = is_commented,
      })
    end
  end

  if #results > 0 then
    return results
  end
  return nil
end

---Parse key=value pairs handling quoted strings properly
---@param str string String containing key=value pairs
---@param allow_dots boolean|nil Allow dots and hyphens in keys (for LABEL)
---@return table[] Array of {key, value, raw_value, quote_offset}
function M.parse_key_value_pairs(str, allow_dots)
  local results = {}
  local i = 1
  local len = #str
  local key_pattern = allow_dots and '[A-Za-z_][A-Za-z0-9_%.%-]*' or '[A-Za-z_][A-Za-z0-9_]*'

  while i <= len do
    -- Skip whitespace
    local ws_end = str:match('^%s*()', i)
    if ws_end then
      i = ws_end
    end
    if i > len then
      break
    end

    -- Match key
    local key = str:match('^(' .. key_pattern .. ')=', i)
    if not key then
      -- Skip non-matching character
      i = i + 1
    else
      i = i + #key + 1 -- Skip key and =

      -- Parse value (quoted or unquoted)
      local value, raw_value, quote_offset
      local char = str:sub(i, i)

      if char == '"' then
        -- Double quoted string
        local end_quote = str:find('"', i + 1, true)
        if end_quote then
          raw_value = str:sub(i, end_quote)
          value = str:sub(i + 1, end_quote - 1)
          quote_offset = 1
          i = end_quote + 1
        else
          -- Unterminated quote, take rest
          raw_value = str:sub(i)
          value = str:sub(i + 1)
          quote_offset = 1
          i = len + 1
        end
      elseif char == "'" then
        -- Single quoted string
        local end_quote = str:find("'", i + 1, true)
        if end_quote then
          raw_value = str:sub(i, end_quote)
          value = str:sub(i + 1, end_quote - 1)
          quote_offset = 1
          i = end_quote + 1
        else
          -- Unterminated quote, take rest
          raw_value = str:sub(i)
          value = str:sub(i + 1)
          quote_offset = 1
          i = len + 1
        end
      else
        -- Unquoted value (until whitespace)
        local val_end = str:find('%s', i)
        if val_end then
          raw_value = str:sub(i, val_end - 1)
          i = val_end
        else
          raw_value = str:sub(i)
          i = len + 1
        end
        value = raw_value
        quote_offset = 0
      end

      table.insert(results, {
        key = key,
        value = value,
        raw_value = raw_value,
        quote_offset = quote_offset,
      })
    end
  end

  return results
end

---Remove quotes from a value and return quote offset
---@param value string
---@return string unquoted_value, number quote_offset
function M.unquote(value)
  if value:match('^".*"$') then
    return value:sub(2, -2), 1
  elseif value:match("^'.*'$") then
    return value:sub(2, -2), 1
  end
  return value, 0
end

---Find position of value in line
---@param line string
---@param prefix string Key or key= prefix to search after
---@param value string
---@param line_start number
---@return {start: number}|nil
function M.find_value_position(line, prefix, value, line_start)
  local prefix_start = line:find(prefix, 1, true)
  if not prefix_start then
    return nil
  end

  local value_start = line:find(value, prefix_start + #prefix, true)
  if not value_start then
    return nil
  end

  return { start = line_start + value_start - 1 }
end

return M
