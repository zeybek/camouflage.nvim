---@mod camouflage.parsers.yaml YAML parser

local M = {}

local config = require('camouflage.config')

---@class MultiLineState
---@field key string The full key path for the multi-line value
---@field indent number The base indentation for content lines
---@field start_index number The start byte index of the multi-line content
---@field lines string[] Collected content lines
---@field line_number number The starting line number (0-based)
---@field is_nested boolean Whether this is a nested key
---@field is_commented boolean Whether this is from a commented line

---@param content string
---@param bufnr number|nil Buffer number for TreeSitter parsing
---@return ParsedVariable[]
function M.parse(content, bufnr)
  -- Try TreeSitter first if buffer is provided
  if bufnr then
    local ts = require('camouflage.treesitter')
    local variables = ts.parse(bufnr, 'yaml', content)
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
  local max_depth = cfg.parsers.yaml.max_depth
  local include_commented = cfg.parsers.include_commented

  lines = lines or vim.split(content, '\n', { plain = true })
  local key_stack = {}
  local current_index = 0
  local multiline_state = nil ---@type MultiLineState|nil

  for line_num, line in ipairs(lines) do
    local line_start = current_index

    -- Check if we're in multi-line mode
    if multiline_state then
      local line_indent = M.get_indentation(line)
      local trimmed = line:match('^%s*(.-)%s*$')

      -- Multi-line content continues if:
      -- 1. Line is empty (preserve empty lines in block)
      -- 2. Line has greater indentation than the key
      if trimmed == '' or line_indent > multiline_state.indent then
        -- Add this line to multi-line content
        table.insert(multiline_state.lines, line)
      else
        -- Multi-line block ended, finalize the variable
        if #multiline_state.lines > 0 then
          local multiline_value = table.concat(multiline_state.lines, '\n')
          -- Trim trailing empty lines but preserve internal structure
          multiline_value = multiline_value:gsub('%s+$', '')

          if #multiline_value > 0 then
            table.insert(variables, {
              key = multiline_state.key,
              value = multiline_value,
              start_index = multiline_state.start_index,
              end_index = multiline_state.start_index + #multiline_value,
              line_number = multiline_state.line_number,
              is_nested = multiline_state.is_nested,
              is_commented = multiline_state.is_commented,
              is_multiline = true,
            })
          end
        end
        multiline_state = nil
        -- Continue processing this line normally (fall through)
      end
    end

    -- Process regular lines (only if not consumed by multi-line)
    if not multiline_state then
      local result =
        M.process_line(line, line_num, line_start, key_stack, max_depth, include_commented)

      if result then
        if result.type == 'variable' then
          table.insert(variables, result.data)
        elseif result.type == 'parent' then
          table.insert(key_stack, result.data)
        elseif result.type == 'multiline_start' then
          -- Start collecting multi-line content
          multiline_state = {
            key = result.data.key,
            indent = result.data.indent,
            start_index = current_index + #line + 1, -- Start after this line
            lines = {},
            line_number = line_num - 1,
            is_nested = result.data.is_nested,
            is_commented = result.data.is_commented or false,
          }
        end
      end
    end

    current_index = current_index + #line + 1
  end

  -- Handle multi-line at end of file
  if multiline_state and #multiline_state.lines > 0 then
    local multiline_value = table.concat(multiline_state.lines, '\n')
    multiline_value = multiline_value:gsub('%s+$', '')

    if #multiline_value > 0 then
      table.insert(variables, {
        key = multiline_state.key,
        value = multiline_value,
        start_index = multiline_state.start_index,
        end_index = multiline_state.start_index + #multiline_value,
        line_number = multiline_state.line_number,
        is_nested = multiline_state.is_nested,
        is_commented = multiline_state.is_commented,
        is_multiline = true,
      })
    end
  end

  return variables
end

---Process a single YAML line and determine its type
---@param line string The line content
---@param line_num number 1-indexed line number
---@param line_start number Byte offset where line starts
---@param key_stack table[] Stack of parent keys with their indentation
---@param max_depth number Maximum nesting depth to parse
---@param include_commented boolean Whether to include commented lines
---@return table|nil Result with type and data, or nil
function M.process_line(line, line_num, line_start, key_stack, max_depth, include_commented)
  local trimmed = line:match('^%s*(.-)%s*$')
  if trimmed == '' or trimmed == '---' or trimmed == '...' then
    return nil
  end

  local is_commented = line:match('^%s*#') ~= nil
  if is_commented and not include_commented then
    return nil
  end

  local indent = M.get_indentation(line)

  while #key_stack > 0 and key_stack[#key_stack].indent >= indent do
    table.remove(key_stack)
  end

  local line_content = is_commented and line:gsub('^%s*#%s*', '') or line
  local parsed = M.parse_line(line_content)

  if not parsed then
    return nil
  end

  local full_key = M.build_key_path(key_stack, parsed.key)
  local current_depth = #key_stack + 1

  if current_depth > max_depth then
    return nil
  end

  -- Check for multi-line block scalar indicators (| or >)
  if parsed.is_multiline_start then
    return {
      type = 'multiline_start',
      data = {
        key = full_key,
        indent = indent,
        is_nested = #key_stack > 0,
        is_commented = is_commented,
      },
    }
  end

  if parsed.has_value and parsed.value then
    local value_offset = is_commented and line:find(parsed.value, line:find(':') + 1)
      or parsed.value_offset

    if value_offset then
      local value_start = line_start + value_offset - 1
      local value_end = value_start + #parsed.value

      return {
        type = 'variable',
        data = {
          key = full_key,
          value = parsed.value,
          start_index = value_start,
          end_index = value_end,
          line_number = line_num - 1,
          is_nested = #key_stack > 0,
          is_commented = is_commented,
        },
      }
    end
  else
    return {
      type = 'parent',
      data = { key = full_key, indent = indent },
    }
  end

  return nil
end

---@param line string
---@return number
function M.get_indentation(line)
  local spaces = line:match('^(%s*)')
  if spaces then
    return #spaces:gsub('\t', '  ')
  end
  return 0
end

---@param line string
---@return {key: string, value: string|nil, has_value: boolean, value_offset: number, is_multiline_start: boolean}|nil
function M.parse_line(line)
  local trimmed = line:match('^%s*(.-)%s*$')

  if trimmed:match('^%-') then
    return nil
  end

  local key, rest = trimmed:match('^([a-zA-Z_][a-zA-Z0-9_%.%-]*)%s*:%s*(.*)$')
  if not key then
    return nil
  end

  local value = rest:match('^%s*(.-)%s*$')
  local has_value = value and #value > 0

  -- Check for multi-line block scalar indicators
  -- | = literal block scalar (preserves newlines)
  -- > = folded block scalar (folds newlines to spaces)
  -- Can have optional modifiers like |-, |+, |2, >-, >+, >2
  local is_multiline_start = false
  if has_value then
    local block_indicator = value:match('^[|>][%-%+]?%d*%s*$')
    if block_indicator then
      is_multiline_start = true
      has_value = false
      value = nil
    end
  end

  if has_value and value then
    if value:match('^".*"$') or value:match("^'.*'$") then
      value = value:sub(2, -2)
    end
  end

  local colon_pos = line:find(':')
  local value_offset = nil
  if has_value and colon_pos then
    local after_colon = line:sub(colon_pos + 1)
    local whitespace = #after_colon - #after_colon:gsub('^%s*', '')

    local raw_value = line:sub(colon_pos + 1):match('^%s*(.-)%s*$')
    if raw_value:match('^["\']') then
      value_offset = colon_pos + whitespace + 2
    else
      value_offset = colon_pos + whitespace + 1
    end
  end

  return {
    key = key,
    value = has_value and value or nil,
    has_value = has_value,
    value_offset = value_offset,
    is_multiline_start = is_multiline_start,
  }
end

---@param stack table[]
---@param current_key string
---@return string
function M.build_key_path(stack, current_key)
  if #stack == 0 then
    return current_key
  end
  return stack[#stack].key .. '.' .. current_key
end

return M
