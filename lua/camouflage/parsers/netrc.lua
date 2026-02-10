---@mod camouflage.parsers.netrc Netrc parser

local M = {}

-- Keywords whose values should be masked
local SENSITIVE_KEYWORDS = {
  login = true,
  password = true,
  account = true,
}

---Parse a quoted string and return the content and full length
---@param str string The string starting with a quote
---@return string|nil content The unquoted content
---@return number length The full length including quotes
local function parse_quoted(str)
  local quote = str:sub(1, 1)
  if quote ~= '"' and quote ~= "'" then
    return nil, 0
  end

  local end_pos = str:find(quote, 2, true)
  if not end_pos then
    return nil, 0
  end

  return str:sub(2, end_pos - 1), end_pos
end

---@param content string
---@param _ string[]|nil Optional pre-split lines (unused, for API compatibility)
---@return ParsedVariable[]
function M.parse(content, _)
  local variables = {}

  -- Track position in content
  local pos = 1
  local content_len = #content

  while pos <= content_len do
    -- Skip whitespace
    local ws_start, ws_end = content:find('^%s+', pos)
    if ws_start then
      pos = ws_end + 1
    end

    if pos > content_len then
      break
    end

    -- Check for comment (# at start of line or after whitespace)
    local char = content:sub(pos, pos)
    if char == '#' then
      -- Skip to end of line
      local eol = content:find('\n', pos)
      if eol then
        pos = eol + 1
      else
        break
      end
    else
      -- Parse token
      local token, token_end
      local first_char = content:sub(pos, pos)

      if first_char == '"' or first_char == "'" then
        -- Quoted token
        local quoted_content, quoted_len = parse_quoted(content:sub(pos))
        if quoted_content then
          token = quoted_content
          token_end = pos + quoted_len - 1
        else
          -- Malformed quote, skip to next whitespace
          local next_ws = content:find('%s', pos)
          token_end = next_ws and next_ws - 1 or content_len
          token = content:sub(pos, token_end)
        end
      else
        -- Unquoted token - read until whitespace
        local next_ws = content:find('%s', pos)
        token_end = next_ws and next_ws - 1 or content_len
        token = content:sub(pos, token_end)
      end

      local token_lower = token:lower()

      -- Check if this is a sensitive keyword
      if SENSITIVE_KEYWORDS[token_lower] then
        -- Next token is the value to mask
        local value_start = token_end + 1

        -- Skip whitespace before value
        local val_ws_start, val_ws_end = content:find('^%s+', value_start)
        if val_ws_start then
          value_start = val_ws_end + 1
        end

        if value_start <= content_len then
          local value_first_char = content:sub(value_start, value_start)
          local value, value_end, next_pos

          if value_first_char == '"' or value_first_char == "'" then
            -- Quoted value
            local quoted_content, quoted_len = parse_quoted(content:sub(value_start))
            if quoted_content then
              value = quoted_content
              -- next_pos should be after the closing quote
              next_pos = value_start + quoted_len
              -- Adjust start/end to exclude quotes for the stored indices
              value_start = value_start + 1
              value_end = value_start + #quoted_content - 1
            else
              -- Malformed quote
              local next_ws = content:find('%s', value_start)
              value_end = next_ws and next_ws - 1 or content_len
              value = content:sub(value_start, value_end)
              next_pos = value_end + 1
            end
          else
            -- Unquoted value
            local next_ws = content:find('%s', value_start)
            value_end = next_ws and next_ws - 1 or content_len
            value = content:sub(value_start, value_end)
            next_pos = value_end + 1
          end

          if value and #value > 0 then
            -- Calculate line number
            local line_num = 1
            for i = 1, value_start - 1 do
              if content:sub(i, i) == '\n' then
                line_num = line_num + 1
              end
            end

            table.insert(variables, {
              key = token_lower,
              value = value,
              start_index = value_start,
              end_index = value_end + 1, -- end_index is exclusive
              line_number = line_num - 1, -- 0-indexed
              is_nested = false,
              is_commented = false,
            })
          end

          pos = next_pos
        else
          pos = token_end + 1
        end
      else
        pos = token_end + 1
      end
    end
  end

  return variables
end

return M
