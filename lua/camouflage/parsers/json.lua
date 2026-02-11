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
  local max_depth = config.get().parsers.json.max_depth

  local ok, parsed = pcall(vim.json.decode, content)
  if ok and parsed then
    ---@type table<string, number> Track last found position per key
    local key_positions = {}
    M.extract_variables(parsed, content, '', 0, max_depth, variables, key_positions)
  else
    M.parse_with_pattern(content, variables)
  end

  return variables
end

---@param obj any
---@param content string
---@param key_prefix string
---@param depth number
---@param max_depth number
---@param variables ParsedVariable[]
---@param key_positions table<string, number> Track last found position per key
function M.extract_variables(obj, content, key_prefix, depth, max_depth, variables, key_positions)
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
        local search_from = key_positions[key] or 1
        local position = M.find_value_position(content, key, value, value_type, search_from)
        if position then
          key_positions[key] = position.end_index + 1
          table.insert(variables, {
            key = full_key,
            value = tostring(value),
            start_index = position.start_index,
            end_index = position.end_index,
            line_number = position.line_number,
            is_nested = depth > 0,
            is_commented = false,
          })
        end
      end
    elseif value_type == 'table' and not islist(value) then
      M.extract_variables(value, content, full_key, depth + 1, max_depth, variables, key_positions)
    end
  end
end

---@param content string
---@param key string
---@param value any
---@param value_type string
---@param search_from number Position to start searching from
---@return {start_index: number, end_index: number, line_number: number}|nil
function M.find_value_position(content, key, value, value_type, search_from)
  local escaped_key = key:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')

  if value_type == 'string' then
    -- Find the key pattern first, then locate the string value using quote matching
    -- This handles escaped quotes properly
    local key_pattern = '"' .. escaped_key .. '"%s*:'
    local key_match_start = content:find(key_pattern, search_from)
    if key_match_start then
      local colon_pos = content:find(':', key_match_start)
      if colon_pos then
        -- Skip whitespace after colon
        local after_colon = content:sub(colon_pos + 1)
        local whitespace = after_colon:match('^%s*') or ''
        local quote_start = colon_pos + #whitespace + 1

        if content:sub(quote_start, quote_start) == '"' then
          local value_content_start = quote_start + 1
          local value_end = M.find_closing_quote(content, value_content_start)
          if value_end then
            -- Verify the raw value matches the decoded value when unescaped
            local raw_value = content:sub(value_content_start, value_end - 1)
            local unescaped = raw_value:gsub('\\"', '"'):gsub('\\\\', '\\')
            if unescaped == value then
              return {
                start_index = value_content_start - 1,
                end_index = value_end - 1,
                line_number = M.get_line_number(content, value_content_start),
              }
            end
          end
        end
      end
    end
  else
    local str_value = tostring(value)
    local escaped_value = str_value:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')
    local pattern = '"' .. escaped_key .. '"%s*:%s*(' .. escaped_value .. ')'
    local match_start, match_end, captured = content:find(pattern, search_from)
    if match_start and captured then
      local value_start = match_end - #str_value + 1
      return {
        start_index = value_start - 1,
        end_index = match_end,
        line_number = M.get_line_number(content, value_start),
      }
    end
  end

  return nil
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

return M
