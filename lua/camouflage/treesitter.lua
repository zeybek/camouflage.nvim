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
    (block_mapping_pair
      key: (_) @key
      value: (block_node
        (block_scalar) @value))
    (flow_pair
      key: (flow_node) @key
      value: (flow_node
        [(plain_scalar) (double_quote_scalar) (single_quote_scalar)] @value))
  ]],
  toml = [[
    (pair
      [(bare_key) (dotted_key) (quoted_key)] @key
      [(string)
       (integer)
       (float)
       (boolean)
       (local_date)
       (local_time)
       (local_date_time)
       (offset_date_time)] @value)
  ]],
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

-- Runtime-registered queries (by language). These take precedence over
-- queries/<lang>/camouflage.scm so 3rd party parsers can ship TS support
-- without touching the runtimepath.
---@type table<string, string>
M.runtime_queries = {}

-- Parsed query cache to avoid re-parsing on every buffer.
---@type table<string, vim.treesitter.Query|false>
local parsed_query_cache = {}

---Register a TreeSitter query for a language at runtime.
---@param lang string
---@param query_string string
function M.register_query(lang, query_string)
  M.runtime_queries[lang] = query_string
  parsed_query_cache[lang] = nil
end

---@param lang string
function M.unregister_query(lang)
  M.runtime_queries[lang] = nil
  parsed_query_cache[lang] = nil
end

---Get query for language. Resolution order:
---  1. Runtime-registered query (M.runtime_queries)
---  2. queries/<lang>/camouflage.scm from runtimepath
---  3. Hardcoded fallback_queries
---@param lang string
---@return vim.treesitter.Query|nil
local function get_query(lang)
  local cached = parsed_query_cache[lang]
  if cached ~= nil then
    return cached or nil
  end

  -- 1. Runtime-registered
  local runtime_q = M.runtime_queries[lang]
  if runtime_q then
    local ok, parsed = pcall(vim.treesitter.query.parse, lang, runtime_q)
    if ok and parsed then
      parsed_query_cache[lang] = parsed
      return parsed
    end
    log.debug('Failed to parse runtime query for %s', lang)
  end

  -- 2. File-based (runtimepath)
  local ok, query = pcall(vim.treesitter.query.get, lang, 'camouflage')
  if ok and query then
    parsed_query_cache[lang] = query
    return query
  end

  -- 3. Hardcoded fallback
  local query_string = fallback_queries[lang]
  if query_string then
    local parse_ok, parsed = pcall(vim.treesitter.query.parse, lang, query_string)
    if parse_ok and parsed then
      log.debug('Using fallback query for %s', lang)
      parsed_query_cache[lang] = parsed
      return parsed
    end
  end

  parsed_query_cache[lang] = false
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

---Register value node types for a language (what counts as a "value", not a container).
---@param lang string
---@param types string[]
function M.register_value_types(lang, types)
  M.value_types[lang] = types
end

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

---@param text string|nil
---@return string|nil
local function normalize_key_text(text)
  if type(text) ~= 'string' then
    return nil
  end
  text = text:match('^%s*(.-)%s*$')
  if text:match('^".*"$') or text:match("^'.*'$") then
    text = text:sub(2, -2)
  end
  return text
end

---@param node userdata
---@param field string
---@return userdata|nil
local function first_field_node(node, field)
  local ok, nodes = pcall(function()
    return node:field(field)
  end)
  if ok and nodes and nodes[1] then
    return nodes[1]
  end
  return nil
end

---@param node userdata
---@param node_type string
---@return userdata|nil
local function first_child_of_type(node, node_type)
  for i = 0, node:child_count() - 1 do
    local child = node:child(i)
    if child and child:type() == node_type then
      return child
    end
  end
  return nil
end

---@param node userdata
---@param node_types table<string, boolean>
---@return userdata|nil
local function first_child_of_types(node, node_types)
  for i = 0, node:child_count() - 1 do
    local child = node:child(i)
    if child and node_types[child:type()] then
      return child
    end
  end
  return nil
end

---@param pair userdata
---@param bufnr number
---@return string|nil
local function pair_key_text(pair, bufnr)
  local key_node = first_field_node(pair, 'key')
  if not key_node then
    return nil
  end
  return normalize_key_text(vim.treesitter.get_node_text(key_node, bufnr))
end

---@param lang string
---@param key_node userdata
---@param bufnr number
---@return string|nil key_path
---@return boolean is_nested
local function derive_pair_key_path(lang, key_node, bufnr)
  if lang ~= 'json' and lang ~= 'yaml' then
    return nil, false
  end

  local pair_types = lang == 'json' and { pair = true }
    or { block_mapping_pair = true, flow_pair = true }

  local parts = {}
  local node = key_node
  while node do
    if pair_types[node:type()] then
      local key = pair_key_text(node, bufnr)
      if key and key ~= '' then
        table.insert(parts, 1, key)
      end
    end
    node = node:parent()
  end

  if #parts == 0 then
    return nil, false
  end
  return table.concat(parts, '.'), #parts > 1
end

local toml_key_types = {
  bare_key = true,
  dotted_key = true,
  quoted_key = true,
}

---@param table_node userdata
---@param bufnr number
---@return string|nil
local function toml_table_key_text(table_node, bufnr)
  local key_node = first_child_of_types(table_node, toml_key_types)
  if not key_node then
    return nil
  end
  return normalize_key_text(vim.treesitter.get_node_text(key_node, bufnr))
end

---@param key_node userdata
---@param fallback_key string
---@param bufnr number
---@return string key_path
---@return boolean is_nested
local function derive_toml_key_path(key_node, fallback_key, bufnr)
  local parts = {}
  local node = key_node:parent()

  while node do
    local node_type = node:type()
    if
      node_type == 'table'
      or node_type == 'table_array'
      or node_type == 'array_table'
      or node_type == 'table_array_element'
    then
      local key = toml_table_key_text(node, bufnr)
      if key and key ~= '' then
        table.insert(parts, 1, key)
      end
    end
    node = node:parent()
  end

  table.insert(parts, fallback_key)
  return table.concat(parts, '.'), #parts > 1 or fallback_key:find('%.') ~= nil
end

---@param element userdata
---@param bufnr number
---@return string|nil
local function xml_element_name(element, bufnr)
  local tag = first_child_of_type(element, 'STag') or first_child_of_type(element, 'EmptyElemTag')
  if not tag then
    return nil
  end
  local name = first_child_of_type(tag, 'Name')
  if not name then
    return nil
  end
  return normalize_key_text(vim.treesitter.get_node_text(name, bufnr))
end

---@param node userdata
---@return userdata|nil
local function xml_enclosing_element(node)
  while node do
    if node:type() == 'element' then
      return node
    end
    node = node:parent()
  end
  return nil
end

---@param element userdata
---@param bufnr number
---@return string[]
local function xml_element_path(element, bufnr)
  local parts = {}
  local node = element
  while node do
    if node:type() == 'element' then
      local name = xml_element_name(node, bufnr)
      if name and name ~= '' then
        table.insert(parts, 1, name)
      end
    end
    node = node:parent()
  end
  return parts
end

---@param key_node userdata
---@param key_text string
---@param bufnr number
---@return string|nil key_path
---@return boolean is_nested
local function derive_xml_key_path(key_node, key_text, bufnr)
  local element = xml_enclosing_element(key_node)
  if not element then
    return nil, false
  end

  local parts = xml_element_path(element, bufnr)
  local parent = key_node:parent()
  if parent and parent:type() == 'Attribute' then
    if #parts == 0 then
      return key_text, false
    end
    return table.concat(parts, '.') .. '@' .. key_text, true
  end

  if #parts == 0 then
    return nil, false
  end
  return table.concat(parts, '.'), #parts > 1
end

---@param lang string
---@param key_node userdata
---@param fallback_key string
---@param bufnr number
---@return string key_path
---@return boolean is_nested
local function derive_key_path(lang, key_node, fallback_key, bufnr)
  local key_path, is_nested
  if lang == 'json' or lang == 'yaml' then
    key_path, is_nested = derive_pair_key_path(lang, key_node, bufnr)
  elseif lang == 'toml' then
    key_path, is_nested = derive_toml_key_path(key_node, fallback_key, bufnr)
  elseif lang == 'xml' then
    key_path, is_nested = derive_xml_key_path(key_node, fallback_key, bufnr)
  end
  return key_path or fallback_key, is_nested == true
end

---@param value string
---@param start_index number
---@param end_index number
---@return string value
---@return number start_index
---@return number end_index
local function normalize_toml_string(value, start_index, end_index)
  if
    (value:sub(1, 3) == '"""' and value:sub(-3) == '"""')
    or (value:sub(1, 3) == "'''" and value:sub(-3) == "'''")
  then
    return value:sub(4, -4), start_index + 3, end_index - 3
  end

  local first = value:sub(1, 1)
  if (first == '"' or first == "'") and value:sub(-1) == first then
    return value:sub(2, -2), start_index + 1, end_index - 1
  end

  return value, start_index, end_index
end

---@param node_text string
---@param start_row number
---@param start_index number
---@param offsets number[]
---@return string value
---@return number start_index
---@return number end_index
local function normalize_yaml_block_scalar(node_text, start_row, start_index, offsets)
  local first_newline = node_text:find('\n', 1, true)
  if not first_newline then
    return '', start_index, start_index
  end

  local value = node_text:sub(first_newline + 1):gsub('%s+$', '')
  local content_start = offsets[start_row + 2] or start_index + first_newline
  return value, content_start, content_start + #value
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

  -- Compute line offsets ONCE, not per captured value: the old code re-split the
  -- whole content and re-summed line lengths inside the loop (O(values x lines)).
  local offsets = require('camouflage.offsets').from_content(content)

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
      current_key_text = normalize_key_text(current_key_text)
    elseif capture_name == 'value' and current_key then
      local node_type = node:type()

      -- Only process value types, not containers (objects/arrays)
      if M.is_value_type(lang, node_type) then
        local start_row, start_col, end_row, end_col = node:range()

        -- Byte offsets via the precomputed line table (node rows are 0-based).
        local start_offset = offsets[start_row + 1]
        local end_offset = offsets[end_row + 1] or #content
        if not start_offset then
          current_key = nil
          current_key_text = nil
          goto continue
        end
        local start_index = start_offset + start_col
        local end_index = end_offset + end_col

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
        elseif lang == 'yaml' and node_type == 'block_scalar' then
          value, start_index, end_index =
            normalize_yaml_block_scalar(node_text, start_row, start_index, offsets)
        elseif lang == 'toml' and node_type == 'string' then
          value, start_index, end_index = normalize_toml_string(value, start_index, end_index)
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
          local key_path, is_nested = derive_key_path(lang, current_key, current_key_text, bufnr)
          table.insert(variables, {
            key = key_path,
            value = value,
            start_index = start_index,
            end_index = end_index,
            line_number = start_row,
            is_nested = is_nested,
            is_commented = false,
            is_multiline = end_row ~= start_row or nil,
          })
        end
      end

      current_key = nil
      current_key_text = nil
    end

    ::continue::
  end

  return variables
end

---Clear parser cache (useful for testing)
---@return nil
function M.clear_cache()
  parser_cache = {}
end

return M
