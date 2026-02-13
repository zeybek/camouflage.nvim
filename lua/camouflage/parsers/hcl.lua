---@mod camouflage.parsers.hcl HCL/Terraform parser

local M = {}

local config = require('camouflage.config')

---@class HeredocState
---@field key string The key for the heredoc value
---@field marker string The heredoc end marker (e.g., EOF)
---@field start_index number The start byte index of the heredoc content
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
    -- Try 'hcl' parser first, then 'terraform'
    local variables = ts.parse(bufnr, 'hcl', content)
    if variables then
      return variables
    end
    variables = ts.parse(bufnr, 'terraform', content)
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
  local current_index = 0
  local block_depth = 0
  local heredoc_state = nil ---@type HeredocState|nil

  for line_num, line in ipairs(lines) do
    local line_start = current_index

    -- Check if we're in heredoc mode
    if heredoc_state then
      local trimmed = line:match('^%s*(.-)%s*$')

      -- Check if this line ends the heredoc
      if trimmed == heredoc_state.marker then
        -- Finalize the heredoc variable
        if #heredoc_state.lines > 0 then
          local heredoc_value = table.concat(heredoc_state.lines, '\n')

          table.insert(variables, {
            key = heredoc_state.key,
            value = heredoc_value,
            start_index = heredoc_state.start_index,
            end_index = heredoc_state.start_index + #heredoc_value,
            line_number = heredoc_state.line_number,
            is_nested = heredoc_state.is_nested,
            is_commented = heredoc_state.is_commented,
            is_multiline = true,
          })
        end
        heredoc_state = nil
      else
        -- Add this line to heredoc content
        table.insert(heredoc_state.lines, line)
      end
    else
      -- Process regular lines (not in heredoc mode)
      local result = M.process_line(line, line_num, line_start, block_depth, include_commented)

      if result then
        if result.type == 'variable' then
          table.insert(variables, result.data)
        elseif result.type == 'heredoc_start' then
          -- Start collecting heredoc content
          heredoc_state = {
            key = result.data.key,
            marker = result.data.marker,
            start_index = current_index + #line + 1, -- Start after this line
            lines = {},
            line_number = line_num - 1,
            is_nested = result.data.is_nested,
            is_commented = result.data.is_commented or false,
          }
        elseif result.type == 'block_open' then
          block_depth = block_depth + result.data.delta
        elseif result.type == 'block_close' then
          block_depth = math.max(0, block_depth + result.data.delta)
        end
      end

      -- Track block depth changes from braces
      local depth_change = M.calculate_depth_change(line)
      block_depth = math.max(0, block_depth + depth_change)
    end

    current_index = current_index + #line + 1
  end

  -- Handle heredoc at end of file (malformed, but be graceful)
  if heredoc_state and #heredoc_state.lines > 0 then
    local heredoc_value = table.concat(heredoc_state.lines, '\n')

    table.insert(variables, {
      key = heredoc_state.key,
      value = heredoc_value,
      start_index = heredoc_state.start_index,
      end_index = heredoc_state.start_index + #heredoc_value,
      line_number = heredoc_state.line_number,
      is_nested = heredoc_state.is_nested,
      is_commented = heredoc_state.is_commented,
      is_multiline = true,
    })
  end

  return variables
end

---Calculate the net change in block depth from braces on a line
---@param line string
---@return number
function M.calculate_depth_change(line)
  -- Remove strings to avoid counting braces inside them
  local cleaned = line:gsub('"[^"]*"', '')
  -- Remove comments
  cleaned = cleaned:gsub('#.*$', '')
  cleaned = cleaned:gsub('//.*$', '')

  local opens = 0
  local closes = 0

  for _ in cleaned:gmatch('{') do
    opens = opens + 1
  end
  for _ in cleaned:gmatch('}') do
    closes = closes + 1
  end

  return opens - closes
end

---Process a single HCL line and determine its type
---@param line string The line content
---@param line_num number 1-indexed line number
---@param line_start number Byte offset where line starts
---@param block_depth number Current block nesting depth
---@param include_commented boolean Whether to include commented lines
---@return table|nil Result with type and data, or nil
function M.process_line(line, line_num, line_start, block_depth, include_commented)
  local trimmed = line:match('^%s*(.-)%s*$')

  if trimmed == '' then
    return nil
  end

  -- Check for comments (# or //)
  local is_commented = trimmed:match('^#') or trimmed:match('^//')
  if is_commented and not include_commented then
    return nil
  end

  -- Skip pure block definitions (resource, variable, module, etc.)
  if M.is_block_definition(trimmed) then
    return { type = 'block_open', data = { delta = 0 } }
  end

  -- Skip closing braces
  if trimmed == '}' then
    return { type = 'block_close', data = { delta = 0 } }
  end

  -- Get content without comment prefix
  local line_content = trimmed
  if is_commented then
    line_content = trimmed:gsub('^#%s*', ''):gsub('^//%s*', '')
  end

  -- Check for heredoc start
  local heredoc_key, heredoc_marker = M.parse_heredoc_start(line_content)
  if heredoc_key and heredoc_marker then
    return {
      type = 'heredoc_start',
      data = {
        key = heredoc_key,
        marker = heredoc_marker,
        is_nested = block_depth > 0,
        is_commented = is_commented and true or false,
      },
    }
  end

  -- Parse key-value pair
  local parsed = M.parse_key_value(line_content, line, line_start)
  if parsed then
    return {
      type = 'variable',
      data = {
        key = parsed.key,
        value = parsed.value,
        start_index = parsed.value_start,
        end_index = parsed.value_end,
        line_number = line_num - 1,
        is_nested = block_depth > 0,
        is_commented = is_commented and true or false,
      },
    }
  end

  return nil
end

---Check if a line is a block definition (resource, variable, module, etc.)
---@param trimmed string Trimmed line content
---@return boolean
function M.is_block_definition(trimmed)
  -- Common HCL/Terraform block types
  local block_patterns = {
    '^resource%s+"[^"]+"%s+"[^"]+"%s*{?',
    '^data%s+"[^"]+"%s+"[^"]+"%s*{?',
    '^variable%s+"[^"]+"%s*{?',
    '^output%s+"[^"]+"%s*{?',
    '^module%s+"[^"]+"%s*{?',
    '^provider%s+"[^"]+"%s*{?',
    '^terraform%s*{',
    '^locals%s*{',
    '^backend%s+"[^"]+"%s*{?',
    -- Generic block pattern: identifier "name" { or identifier {
    '^[a-zA-Z_][a-zA-Z0-9_%-]*%s+"[^"]+"%s*{',
    '^[a-zA-Z_][a-zA-Z0-9_%-]*%s*{%s*$',
  }

  for _, pattern in ipairs(block_patterns) do
    if trimmed:match(pattern) then
      return true
    end
  end

  return false
end

---Parse heredoc start pattern
---@param line_content string
---@return string|nil key, string|nil marker
function M.parse_heredoc_start(line_content)
  -- Match: key = <<EOF or key = <<-EOF (indented heredoc)
  local key, marker =
    line_content:match('^%s*([a-zA-Z_][a-zA-Z0-9_%-]*)%s*=%s*<<%-?([A-Za-z_][A-Za-z0-9_]*)%s*$')
  return key, marker
end

---Parse a key-value pair from an HCL line
---@param line_content string The line content (without comment prefix)
---@param original_line string The original line
---@param line_start number Byte offset where line starts
---@return {key: string, value: string, value_start: number, value_end: number}|nil
function M.parse_key_value(line_content, original_line, line_start)
  local key, value
  local quote_offset = 0

  -- Try quoted string value first: key = "value"
  key, value = line_content:match('^%s*([a-zA-Z_][a-zA-Z0-9_%-]*)%s*=%s*"([^"]*)"')
  if key and value then
    quote_offset = 1
  end

  -- Try unquoted value: key = 123 or key = true or key = var.something
  if not key then
    local raw_key, raw_value =
      line_content:match('^%s*([a-zA-Z_][a-zA-Z0-9_%-]*)%s*=%s*([^#%s][^#]*)')
    if raw_key and raw_value then
      -- Trim trailing whitespace
      raw_value = raw_value:match('^(.-)%s*$')

      -- Skip values that are variable references (var.xxx, local.xxx, etc.)
      if M.is_variable_reference(raw_value) then
        return nil
      end

      -- Skip values that are function calls
      if M.is_function_call(raw_value) then
        return nil
      end

      -- Skip complex expressions (containing interpolation, etc.)
      if raw_value:match('%$%{') then
        return nil
      end

      -- Skip arrays and objects
      if raw_value:match('^%[') or raw_value:match('^{') then
        return nil
      end

      key = raw_key
      value = raw_value
      quote_offset = 0
    end
  end

  if not key or not value then
    return nil
  end

  -- Calculate byte positions
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

---Check if a value is a variable reference
---@param value string
---@return boolean
function M.is_variable_reference(value)
  local ref_patterns = {
    '^var%.',
    '^local%.',
    '^module%.',
    '^data%.',
    '^each%.',
    '^count%.',
    '^self%.',
    '^path%.',
    '^terraform%.',
    '^aws_',
    '^azurerm_',
    '^google_',
  }

  for _, pattern in ipairs(ref_patterns) do
    if value:match(pattern) then
      return true
    end
  end

  return false
end

---Check if a value is a function call
---@param value string
---@return boolean
function M.is_function_call(value)
  -- Function calls look like: func(...) or func(
  return value:match('^[a-zA-Z_][a-zA-Z0-9_]*%s*%(') ~= nil
end

return M
