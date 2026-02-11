---@mod camouflage.treesitter TreeSitter utilities
---@brief [[
--- Provides TreeSitter-based parsing for supported file formats.
--- Falls back to regex parsing when TreeSitter is not available.
---@brief ]]

local M = {}

---@type table<string, boolean>
local parser_cache = {}

-- TreeSitter queries for each language
M.queries = {
  json = '(pair key: (string) @key value: (_) @value)',
  yaml = '(block_mapping_pair key: (_) @key value: (_) @value)',
  toml = '(pair key: (_) @key value: (_) @value)',
}

-- Node types that contain actual values (not containers)
M.value_types = {
  json = { 'string', 'number', 'true', 'false', 'null' },
  yaml = {
    'string_scalar',
    'double_quote_scalar',
    'single_quote_scalar',
    'integer_scalar',
    'float_scalar',
    'boolean_scalar',
    'block_scalar',
  },
  toml = {
    'string',
    'integer',
    'float',
    'boolean',
    'local_date',
    'local_time',
    'local_date_time',
    'offset_date_time',
  },
}

---Check if TreeSitter parser is available for a language
---@param lang string Language name (e.g., 'json', 'yaml', 'toml')
---@return boolean
function M.has_parser(lang)
  if parser_cache[lang] ~= nil then
    return parser_cache[lang]
  end

  -- Try to get the parser - if it works, we have it
  local ok = pcall(vim.treesitter.language.inspect, lang)
  parser_cache[lang] = ok
  return ok
end

---Check if a node type is a value type (not a container)
---@param lang string Language name
---@param node_type string Node type
---@return boolean
function M.is_value_type(lang, node_type)
  local types = M.value_types[lang]
  if not types then
    return true -- If we don't know, assume it's a value
  end
  for _, t in ipairs(types) do
    if t == node_type then
      return true
    end
  end
  return false
end

---Parse a buffer using TreeSitter and extract key-value pairs
---@param bufnr number Buffer number
---@param lang string Language name
---@param content string Buffer content
---@return ParsedVariable[]|nil Returns nil if TreeSitter is not available
function M.parse(bufnr, lang, content)
  if not M.has_parser(lang) then
    return nil
  end

  local query_string = M.queries[lang]
  if not query_string then
    return nil
  end

  -- Get parser and parse
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    return nil
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return nil
  end

  local root = trees[1]:root()

  -- Parse query
  local query_ok, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not query_ok or not query then
    return nil
  end

  local variables = {}
  local current_key = nil
  local current_key_text = nil

  for id, node in query:iter_captures(root, bufnr) do
    local capture_name = query.captures[id]
    local node_text = vim.treesitter.get_node_text(node, bufnr)

    if capture_name == 'key' then
      -- Store key for next value
      current_key = node
      current_key_text = node_text
      -- Remove quotes from JSON keys
      if lang == 'json' and current_key_text:match('^".*"$') then
        current_key_text = current_key_text:sub(2, -2)
      end
    elseif capture_name == 'value' and current_key then
      local node_type = node:type()

      -- Only process value types, not containers (objects/arrays)
      if M.is_value_type(lang, node_type) then
        local start_row, start_col, end_row, end_col = node:range()

        -- Calculate byte offsets
        local lines = vim.split(content, '\n', { plain = true })
        local start_index = 0
        for i = 1, start_row do
          start_index = start_index + #lines[i] + 1
        end
        start_index = start_index + start_col

        local end_index = 0
        for i = 1, end_row do
          end_index = end_index + #lines[i] + 1
        end
        end_index = end_index + end_col

        -- Get actual value (remove quotes for strings)
        local value = node_text
        if lang == 'json' and value:match('^".*"$') then
          value = value:sub(2, -2)
          -- Adjust positions to exclude quotes
          start_index = start_index + 1
          end_index = end_index - 1
        elseif
          lang == 'yaml'
          and (node_type == 'double_quote_scalar' or node_type == 'single_quote_scalar')
        then
          value = value:sub(2, -2)
          start_index = start_index + 1
          end_index = end_index - 1
        end

        -- Skip empty values
        if value ~= '' and not value:match('^%s*$') then
          table.insert(variables, {
            key = current_key_text,
            value = value,
            start_index = start_index,
            end_index = end_index,
            line_number = start_row,
            is_nested = false, -- TODO: detect nesting
            is_commented = false,
          })
        end
      end

      current_key = nil
      current_key_text = nil
    end
  end

  return variables
end

---Clear parser cache (useful for testing)
---@return nil
function M.clear_cache()
  parser_cache = {}
end

return M
