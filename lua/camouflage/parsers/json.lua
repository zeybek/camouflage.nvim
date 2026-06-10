---@mod camouflage.parsers.json JSON parser

local M = {}

local config = require('camouflage.config')

-- Compatibility: vim.islist was added in Neovim 0.10, use vim.tbl_islist for 0.9.x
local islist = vim.islist or vim.tbl_islist

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

  local ok, parsed = pcall(vim.json.decode, content)
  if ok and parsed then
    -- Index every key occurrence by document position up front, then consume
    -- one occurrence per decoded (key, value). This is order-independent: the
    -- decode walk (pairs()) drives nesting/typing, but positions come from the
    -- document, so duplicate key names in different objects can never collide.
    local occurrences = M.collect_key_occurrences(content)
    M.extract_variables(parsed, content, '', 0, max_depth, variables, occurrences)
  else
    M.parse_with_pattern(content, variables)
  end

  return variables
end

---Collect every object-key occurrence in document order, escape-aware.
---A string token "..." is a key iff the next non-whitespace char after its
---closing quote is ':'. Returns a map of short-key -> ascending list of
---{ qs = opening-quote pos, qe = closing-quote pos } (1-based).
---@param content string
---@return table<string, table[]>
function M.collect_key_occurrences(content)
  local occurrences = {}
  local pos = 1
  local len = #content

  while pos <= len do
    local qs = content:find('"', pos)
    if not qs then
      break
    end
    local qe = M.find_closing_quote(content, qs + 1)
    if not qe then
      break
    end

    local after = content:find('%S', qe + 1)
    if after and content:sub(after, after) == ':' then
      local raw_key = content:sub(qs + 1, qe - 1)
      local key = raw_key:gsub('\\"', '"'):gsub('\\\\', '\\')
      local list = occurrences[key]
      if not list then
        list = {}
        occurrences[key] = list
      end
      list[#list + 1] = { qs = qs, qe = qe }
      pos = after + 1
    else
      -- A value string (or any non-key string): skip past its closing quote.
      pos = qe + 1
    end
  end

  return occurrences
end

---@param obj any
---@param content string
---@param key_prefix string
---@param depth number
---@param max_depth number
---@param variables ParsedVariable[]
---@param occurrences table<string, table[]> Document-order key positions
function M.extract_variables(obj, content, key_prefix, depth, max_depth, variables, occurrences)
  if depth > max_depth or type(obj) ~= 'table' then
    return
  end

  for key, value in pairs(obj) do
    local full_key = key_prefix == '' and key or (key_prefix .. '.' .. key)
    local value_type = type(value)

    if value_type == 'string' or value_type == 'number' or value_type == 'boolean' then
      -- Skip empty or whitespace-only string values
      local should_skip = value_type == 'string' and (value == '' or value:match('^%s*$'))
      if not should_skip then
        local list = occurrences[key]
        if list then
          for _, occ in ipairs(list) do
            if not occ.consumed then
              local position = M.value_at_occurrence(content, occ, value, value_type)
              if position then
                occ.consumed = true
                table.insert(variables, {
                  key = full_key,
                  value = tostring(value),
                  start_index = position.start_index,
                  end_index = position.end_index,
                  line_number = position.line_number,
                  is_nested = depth > 0,
                  is_commented = false,
                })
                break
              end
            end
          end
        end
      end
    elseif value_type == 'table' and not islist(value) then
      M.extract_variables(value, content, full_key, depth + 1, max_depth, variables, occurrences)
    end
  end
end

---Resolve the scalar value position for a key occurrence, if the value there
---matches the expected decoded value. Structural and position-anchored: it
---reads the ':' and value immediately after the key occurrence, never searching
---forward, so it cannot drift onto another object's identically-named key.
---@param content string
---@param occ table { qs, qe } occurrence (1-based quote positions)
---@param value any Decoded value
---@param value_type string 'string'|'number'|'boolean'
---@return {start_index: number, end_index: number, line_number: number}|nil
function M.value_at_occurrence(content, occ, value, value_type)
  -- Only whitespace may sit between the key's closing quote and the ':'.
  local _, colon_end = content:find('^%s*:', occ.qe + 1)
  if not colon_end then
    return nil
  end
  local value_start = content:find('%S', colon_end + 1)
  if not value_start then
    return nil
  end

  if value_type == 'string' then
    if content:sub(value_start, value_start) ~= '"' then
      return nil
    end
    local value_content_start = value_start + 1
    local value_end = M.find_closing_quote(content, value_content_start)
    if not value_end then
      return nil
    end
    -- Verify the raw value matches the decoded value when unescaped
    local raw_value = content:sub(value_content_start, value_end - 1)
    local unescaped = raw_value:gsub('\\"', '"'):gsub('\\\\', '\\')
    if unescaped ~= value then
      return nil
    end
    return {
      start_index = value_content_start - 1,
      end_index = value_end - 1,
      line_number = M.get_line_number(content, value_content_start),
    }
  else
    local str_value = tostring(value)
    if content:sub(value_start, value_start + #str_value - 1) ~= str_value then
      return nil
    end
    -- The literal must end at a JSON delimiter so value 1 does not match the
    -- leading '1' of 12.
    local after = content:sub(value_start + #str_value, value_start + #str_value)
    if after ~= '' and not after:match('[%s,%]}]') then
      return nil
    end
    return {
      start_index = value_start - 1,
      end_index = value_start + #str_value - 1,
      line_number = M.get_line_number(content, value_start),
    }
  end
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
