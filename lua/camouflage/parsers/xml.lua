---@mod camouflage.parsers.xml XML parser

local M = {}

local config = require('camouflage.config')

---@param content string
---@param bufnr number|nil Buffer number for TreeSitter parsing
---@return ParsedVariable[]
function M.parse(content, bufnr)
  -- Try TreeSitter first if buffer is provided
  if bufnr then
    local ts = require('camouflage.treesitter')
    local variables = ts.parse(bufnr, 'xml', content)
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
  local max_depth = cfg.parsers.xml and cfg.parsers.xml.max_depth or 10

  -- Parse element content: <tag>value</tag>
  M.parse_elements(content, variables, max_depth)

  -- Parse attributes: attr="value"
  M.parse_attributes(content, variables)

  return variables
end

---Parse element content like <tag>value</tag>
---@param content string
---@param variables ParsedVariable[]
---@param max_depth number
function M.parse_elements(content, variables, max_depth)
  -- Build a simple DOM-like structure to track parent paths
  local lines = vim.split(content, '\n', { plain = true })
  local tag_stack = {} ---@type string[]
  local current_index = 0

  -- Tag pattern includes dots for names like db.password
  local tag_pattern = '[%w_%-:.]+' -- Note: includes dot for tag names

  for line_num, line in ipairs(lines) do
    local line_start = current_index

    -- Remove XML declaration/processing instructions from line for tag parsing
    -- but keep track of where actual content starts for position calculations
    local processing_line = line:gsub('<%?[^?]*%?>', '')

    -- First, find all inline element content and their parent context
    -- by scanning for content that contains <outer>...<inner>value</inner>...</outer>
    M.parse_inline_elements(
      processing_line,
      line,
      line_start,
      line_num,
      tag_stack,
      max_depth,
      variables,
      tag_pattern
    )

    -- Track opening tags that span multiple lines (no closing tag on same line)
    for tag_name in processing_line:gmatch('<(' .. tag_pattern .. ')[^/>]*>') do
      -- Check if this tag has a closing tag on the same line
      local has_close_on_line = processing_line:match('</' .. M.escape_pattern(tag_name) .. '%s*>')
      if not has_close_on_line then
        if #tag_stack < max_depth then
          table.insert(tag_stack, tag_name)
        end
      end
    end

    -- Track closing tags that close multi-line elements
    for tag_name in processing_line:gmatch('</(' .. tag_pattern .. ')%s*>') do
      -- Only pop if there's no opening tag on the same line (multi-line element)
      local has_open_on_line = processing_line:match('<' .. M.escape_pattern(tag_name) .. '[^/>]*>')
      if not has_open_on_line then
        -- Pop matching tag from stack
        for i = #tag_stack, 1, -1 do
          if tag_stack[i] == tag_name then
            table.remove(tag_stack, i)
            break
          end
        end
      end
    end

    current_index = current_index + #line + 1
  end
end

---Parse inline elements within a line, tracking nested structure
---@param processing_line string Line with declarations removed
---@param original_line string Original line for position calculation
---@param line_start number Byte offset where line starts
---@param line_num number 1-indexed line number
---@param parent_stack string[] Parent tag stack from previous lines
---@param max_depth number Maximum depth
---@param variables ParsedVariable[] Output array
---@param tag_pattern string Pattern for tag names
function M.parse_inline_elements(
  processing_line,
  original_line,
  line_start,
  line_num,
  parent_stack,
  max_depth,
  variables,
  tag_pattern
)
  -- Build local context for this line by tracking open/close tags
  local local_stack = {}
  local pos = 1

  while pos <= #processing_line do
    -- Look for next tag
    local open_start, open_end, tag_name = processing_line:find('<(' .. tag_pattern .. ')>', pos)
    local self_close_start, self_close_end =
      processing_line:find('<' .. tag_pattern .. '[^>]*/>', pos)

    if not open_start then
      break
    end

    -- Skip self-closing tags
    if self_close_start and self_close_start < open_start then
      pos = self_close_end + 1
    else
      -- Found opening tag <tag>
      -- Look for matching close tag </tag>
      local close_pattern = '</' .. M.escape_pattern(tag_name) .. '%s*>'
      local close_start, close_end = processing_line:find(close_pattern, open_end)

      if close_start then
        -- Extract content between tags
        local content_between = processing_line:sub(open_end + 1, close_start - 1)

        -- Check if content has no child elements (just text)
        if not content_between:match('<') then
          -- This is a leaf element with text content
          local value = content_between
          if value and not value:match('^%s*$') then
            -- Build full key path: parent_stack + local_stack + tag_name
            local full_stack = vim.list_extend(vim.list_extend({}, parent_stack), local_stack)
            local full_key = M.build_key_path(full_stack, tag_name)

            -- Find position in original line
            local value_start_in_line = original_line:find('>' .. M.escape_pattern(value) .. '<')
            if value_start_in_line then
              local value_start = line_start + value_start_in_line -- 0-indexed
              local value_end = value_start + #value
              table.insert(variables, {
                key = full_key,
                value = value,
                start_index = value_start,
                end_index = value_end,
                line_number = line_num - 1,
                is_nested = #full_stack > 0,
                is_commented = false,
              })
            end
          end
          -- Move past this complete element
          pos = close_end + 1
        else
          -- This element has children - add to local stack and continue inside
          if #parent_stack + #local_stack < max_depth then
            table.insert(local_stack, tag_name)
          end
          -- Continue from right after opening tag to process children
          pos = open_end + 1
        end
      else
        -- No closing tag found on this line - element spans lines
        -- Don't add to local stack (will be handled by main function)
        pos = open_end + 1
      end
    end
  end
end

---Parse attributes like attr="value" or attr='value'
---@param content string
---@param variables ParsedVariable[]
function M.parse_attributes(content, variables)
  local current_pos = 1

  while current_pos <= #content do
    -- Find attribute pattern: name="value" or name='value'
    local attr_start, attr_end, attr_name, quote, attr_value =
      content:find('([%w_%-:]+)%s*=%s*(["\'])([^"\']*)["\']', current_pos)

    if not attr_start then
      break
    end

    -- Check if this attribute is inside an XML declaration (<?xml ... ?>)
    local is_in_declaration = M.is_in_xml_declaration(content, attr_start)

    -- Skip XML declaration attributes
    if not is_in_declaration then
      -- Skip empty/whitespace values
      if attr_value and not attr_value:match('^%s*$') then
        -- Calculate positions
        local value_start = content:find(quote .. M.escape_pattern(attr_value) .. quote, attr_start)
        if value_start then
          value_start = value_start + 1 -- Skip opening quote
          local value_end = value_start + #attr_value
          local line_number = M.get_line_number(content, value_start)

          table.insert(variables, {
            key = attr_name,
            value = attr_value,
            start_index = value_start - 1, -- 0-indexed
            end_index = value_end - 1, -- 0-indexed
            line_number = line_number,
            is_nested = false,
            is_commented = false,
          })
        end
      end
    end

    current_pos = attr_end + 1
  end
end

---Check if a position is inside an XML declaration (<?xml ... ?>)
---@param content string
---@param pos number Position to check
---@return boolean
function M.is_in_xml_declaration(content, pos)
  -- Find the most recent <? before pos
  local decl_start = nil
  local search_pos = 1
  while true do
    local start = content:find('<%?', search_pos)
    if not start or start >= pos then
      break
    end
    decl_start = start
    search_pos = start + 1
  end

  if not decl_start then
    return false
  end

  -- Find the closing ?> after this declaration
  local decl_end = content:find('%?>', decl_start)
  if decl_end and pos < decl_end then
    return true
  end

  return false
end

---Build the full key path from tag stack
---@param stack string[]
---@param current_tag string
---@return string
function M.build_key_path(stack, current_tag)
  if #stack == 0 then
    return current_tag
  end
  return table.concat(stack, '.') .. '.' .. current_tag
end

---Escape special Lua pattern characters
---@param str string
---@return string
function M.escape_pattern(str)
  return (str:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1'))
end

---Get 0-indexed line number for a position
---@param content string
---@param index number 1-indexed position
---@return number
function M.get_line_number(content, index)
  local _, count = content:sub(1, index):gsub('\n', '')
  return count
end

return M
