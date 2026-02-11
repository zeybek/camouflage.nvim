---@mod camouflage.parsers.custom Custom pattern parser

local M = {}

local config = require('camouflage.config')

---@param content string
---@param pattern_config CamouflageCustomPatternConfig
---@return ParsedVariable[]
function M.parse(content, pattern_config)
  local variables = {}
  local lines = vim.split(content, '\n', { plain = true })
  local current_index = 0
  local custom_counter = 0

  for line_num, line in ipairs(lines) do
    -- Find all matches in the line
    local search_start = 1
    while search_start <= #line do
      local match_start, match_end, c1, c2, c3, c4, c5 =
        line:find(pattern_config.pattern, search_start)
      if not match_start then
        break
      end

      -- Collect captures into a table
      local captures = { c1, c2, c3, c4, c5 }

      -- Get key and value based on capture groups
      local key, value

      if pattern_config.key_capture and captures[pattern_config.key_capture] then
        key = captures[pattern_config.key_capture]
      else
        custom_counter = custom_counter + 1
        key = 'custom_' .. custom_counter
      end

      if pattern_config.value_capture and captures[pattern_config.value_capture] then
        value = captures[pattern_config.value_capture]
      end

      -- Only add if we have a valid value
      if value and #value > 0 then
        -- Find the position of the value in the line
        local value_pos = line:find(value, match_start, true)
        if value_pos then
          table.insert(variables, {
            key = key,
            value = value,
            start_index = current_index + value_pos - 1,
            end_index = current_index + value_pos - 1 + #value,
            line_number = line_num - 1, -- 0-indexed
            is_nested = false,
            is_commented = false,
          })
        end
      end

      -- Move to next potential match
      search_start = match_end + 1
    end

    current_index = current_index + #line + 1
  end

  return variables
end

---@param filename string
---@param file_pattern string|string[]
---@return boolean
local function matches_file_pattern(filename, file_pattern)
  local parsers = require('camouflage.parsers')
  local basename = vim.fn.fnamemodify(filename, ':t')

  local patterns = file_pattern
  if type(patterns) == 'string' then
    patterns = { patterns }
  end

  for _, pattern in ipairs(patterns) do
    if parsers.match_pattern(basename, pattern) then
      return true
    end
  end

  return false
end

---@param filename string
---@return CamouflageCustomPatternConfig|nil
function M.find_matching_pattern(filename)
  local cfg = config.get()
  local custom_patterns = cfg.custom_patterns or {}

  for _, pattern_config in ipairs(custom_patterns) do
    if matches_file_pattern(filename, pattern_config.file_pattern) then
      return pattern_config
    end
  end

  return nil
end

return M
