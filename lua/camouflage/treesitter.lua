---@mod camouflage.treesitter TreeSitter utilities
---@brief [[
--- Provides TreeSitter-based parsing for supported file formats.
--- Falls back to regex parsing when TreeSitter is not available.
---@brief ]]

local log = require('camouflage.log')

local M = {}

---@type table<string, boolean>
local parser_cache = {}

-- Fallback TreeSitter queries for each language (used when no query file exists)
local fallback_queries = {
  json = '(pair key: (string) @key value: (_) @value)',
  yaml = [[
    (block_mapping_pair
      key: (_) @key
      value: (flow_node
        [(plain_scalar) (double_quote_scalar) (single_quote_scalar)] @value))
    (flow_pair
      key: (flow_node) @key
      value: (flow_node
        [(plain_scalar) (double_quote_scalar) (single_quote_scalar)] @value))
  ]],
  toml = '(pair key: (_) @key value: (_) @value)',
  xml = [[
    (element
      (STag (Name) @key)
      (content (CharData) @value)
      (ETag))
    (Attribute
      (Name) @key
      (AttValue) @value)
  ]],
  http = '(variable_declaration name: (identifier) @key value: (value) @value)',
  hcl = [[
    ; Simple attribute: key = "value"
    (attribute
      (identifier) @key
      (expression) @value)
  ]],
  -- Terraform uses the same syntax as HCL
  terraform = [[
    ; Simple attribute: key = "value"
    (attribute
      (identifier) @key
      (expression) @value)
  ]],
  dockerfile = [[
    ; ENV KEY=value
    (env_instruction
      (env_pair
        name: (_) @key
        value: (_) @value))

    ; ARG KEY=default
    (arg_instruction
      name: (_) @key
      default: (_) @value)

    ; LABEL key=value
    (label_instruction
      (label_pair
        key: (_) @key
        value: (_) @value))
  ]],
}

---Get query for language (file-based with fallback)
---@param lang string
---@return vim.treesitter.Query|nil
local function get_query(lang)
  -- Try to load from file first
  local ok, query = pcall(vim.treesitter.query.get, lang, 'camouflage')
  if ok and query then
    return query
  end

  -- Fallback to inline query
  local query_string = fallback_queries[lang]
  if query_string then
    local parse_ok, parsed = pcall(vim.treesitter.query.parse, lang, query_string)
    if parse_ok and parsed then
      log.debug('Using fallback query for %s', lang)
      return parsed
    end
  end

  return nil
end

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
    'plain_scalar', -- For flow style and unquoted values
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
  xml = { 'CharData', 'AttValue' },
  http = { 'value' },
  hcl = {
    'template_literal',
    'literal_value',
    'numeric_lit',
    'bool_lit',
    'string_lit',
    'quoted_template',
    'heredoc_template',
  },
  -- Terraform uses the same value types as HCL
  terraform = {
    'template_literal',
    'literal_value',
    'numeric_lit',
    'bool_lit',
    'string_lit',
    'quoted_template',
    'heredoc_template',
  },
  dockerfile = {
    'double_quoted_string',
    'single_quoted_string',
    'unquoted_string',
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
  local ok, err = pcall(vim.treesitter.language.inspect, lang)
  if not ok then
    log.debug('TreeSitter parser not available for %s: %s', lang, err)
  end
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

  local query = get_query(lang)
  if not query then
    return nil
  end

  -- Get parser and parse
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    if not ok then
      log.pcall_error('treesitter.get_parser', parser, { bufnr = bufnr, lang = lang })
    end
    return nil
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return nil
  end

  local root = trees[1]:root()

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
        elseif lang == 'xml' and node_type == 'AttValue' then
          -- XML attribute values include quotes: "value" or 'value'
          if value:match('^".*"$') or value:match("^'.*'$") then
            value = value:sub(2, -2)
            start_index = start_index + 1
            end_index = end_index - 1
          end
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
