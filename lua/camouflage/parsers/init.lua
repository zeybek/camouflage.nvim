---@mod camouflage.parsers Parser registry

local M = {}

local config = require('camouflage.config')

---@class ParsedVariable
---@field key string
---@field value string
---@field start_index number
---@field end_index number
---@field line_number number
---@field is_nested boolean
---@field is_commented boolean
---@field is_multiline boolean|nil

---@class CamouflageTSParserSpec
---@field lang string
---@field query? string
---@field query_file? string

---@class CamouflageParserEntry
---@field name string
---@field parser table
---@field filetypes? string[]
---@field file_patterns? string[]
---@field priority? integer
---@field treesitter? CamouflageTSParserSpec
---@field source? string  -- 'builtin' | 'user'

---@type table<string, table>
M.parsers = {}

-- Rich metadata registry. M.parsers stays as the primary storage for
-- backward compatibility (tests and external callers read it directly).
---@type table<string, CamouflageParserEntry>
M.entries = {}

local DEFAULT_PRIORITY = 50

-- Simple cache for find_parser_for_file to avoid repeated lookups
---@type {filename: string|nil, parser: table|nil, parser_name: string|nil}
local parser_cache = { filename = nil, parser = nil, parser_name = nil }

---Register a parser.
---
---Supports two call forms:
---  - register(name, parser_table)         -- legacy
---  - register(spec) where spec has .name  -- new, accepts metadata
---@param name_or_spec string|CamouflageParserEntry
---@param parser? table
function M.register(name_or_spec, parser)
  local entry
  if type(name_or_spec) == 'string' then
    entry = { name = name_or_spec, parser = parser }
  else
    entry = vim.deepcopy(name_or_spec)
    -- Allow passing parser table directly as the spec (must have .parse and .name)
    if not entry.parser and type(entry.parse) == 'function' then
      entry.parser = { parse = entry.parse }
    end
  end

  assert(entry.name, 'parser registration requires a name')
  assert(
    entry.parser and type(entry.parser.parse) == 'function',
    'parser must have a parse function'
  )

  entry.priority = entry.priority or DEFAULT_PRIORITY
  entry.source = entry.source or 'user'

  M.parsers[entry.name] = entry.parser
  M.entries[entry.name] = entry
  M.clear_cache()
end

---@param name string
function M.unregister(name)
  M.parsers[name] = nil
  M.entries[name] = nil
  M.clear_cache()
end

---@param name string
---@return table|nil
function M.get(name)
  return M.parsers[name]
end

---@return CamouflageParserEntry[]
function M.list()
  local out = {}
  for _, entry in pairs(M.entries) do
    table.insert(out, entry)
  end
  table.sort(out, function(a, b)
    if (a.priority or 0) ~= (b.priority or 0) then
      return (a.priority or 0) > (b.priority or 0)
    end
    return a.name < b.name
  end)
  return out
end

---@param filename string
---@return table|nil, string|nil
function M.find_parser_for_file(filename)
  -- Check cache first
  if parser_cache.filename == filename then
    return parser_cache.parser, parser_cache.parser_name
  end

  local cfg = config.get()
  local basename = vim.fn.fnamemodify(filename, ':t')

  -- Always exclude project config file from masking
  local project_config_filename = (cfg.project_config and cfg.project_config.filename)
    or '.camouflage.yaml'
  if basename == project_config_filename then
    parser_cache.filename = filename
    parser_cache.parser = nil
    parser_cache.parser_name = nil
    return nil, nil
  end

  for _, pattern_config in ipairs(cfg.patterns) do
    local patterns = pattern_config.file_pattern
    if type(patterns) == 'string' then
      patterns = { patterns }
    end

    for _, pattern in ipairs(patterns) do
      if M.match_pattern(basename, pattern) then
        local parser = M.parsers[pattern_config.parser]
        if parser then
          -- Update cache
          parser_cache.filename = filename
          parser_cache.parser = parser
          parser_cache.parser_name = pattern_config.parser
          return parser, pattern_config.parser
        end
      end
    end
  end

  -- Try parsers registered with metadata (file_patterns / filetypes).
  -- Sorted by priority desc so user-registered parsers can override.
  local entry_match = M.find_entry_for_file(filename)
  if entry_match then
    parser_cache.filename = filename
    parser_cache.parser = entry_match.parser
    parser_cache.parser_name = entry_match.name
    return entry_match.parser, entry_match.name
  end

  -- If no built-in parser found, check custom patterns
  local custom = require('camouflage.parsers.custom')
  local custom_pattern = custom.find_matching_pattern(filename)
  if custom_pattern then
    -- Create a wrapper parser that calls custom.parse with the pattern config
    local custom_parser = {
      parse = function(content, _bufnr)
        return custom.parse(content, custom_pattern)
      end,
    }
    -- Update cache
    parser_cache.filename = filename
    parser_cache.parser = custom_parser
    parser_cache.parser_name = 'custom'
    return custom_parser, 'custom'
  end

  -- Cache negative result too
  parser_cache.filename = filename
  parser_cache.parser = nil
  parser_cache.parser_name = nil
  return nil, nil
end

---Find a parser entry whose registered filetypes/file_patterns match the file.
---Higher priority wins; ties resolved by user-source before builtin.
---@param filename string
---@param filetype? string
---@return CamouflageParserEntry|nil
function M.find_entry_for_file(filename, filetype)
  local basename = vim.fn.fnamemodify(filename, ':t')
  local candidates = {}

  for _, entry in pairs(M.entries) do
    local matched = false

    if filetype and entry.filetypes then
      for _, ft in ipairs(entry.filetypes) do
        if ft == filetype then
          matched = true
          break
        end
      end
    end

    if not matched and entry.file_patterns then
      for _, pat in ipairs(entry.file_patterns) do
        if M.match_pattern(basename, pat) then
          matched = true
          break
        end
      end
    end

    if matched then
      table.insert(candidates, entry)
    end
  end

  if #candidates == 0 then
    return nil
  end

  table.sort(candidates, function(a, b)
    local pa, pb = a.priority or DEFAULT_PRIORITY, b.priority or DEFAULT_PRIORITY
    if pa ~= pb then
      return pa > pb
    end
    -- user-registered beats builtin on tie
    if a.source ~= b.source then
      return a.source == 'user'
    end
    return a.name < b.name
  end)

  return candidates[1]
end

---@param filename string
---@param pattern string
---@return boolean
function M.match_pattern(filename, pattern)
  local lua_pattern = pattern:gsub('%.', '%%.'):gsub('%*', '.*'):gsub('%?', '.')

  if pattern:match('^%.') and pattern:match('%*$') then
    local prefix = pattern:gsub('%*$', ''):gsub('%.', '%%.')
    return filename:match('^' .. prefix) ~= nil
  end

  if pattern:match('^%*%.') then
    local suffix = pattern:gsub('^%*', ''):gsub('%.', '%%.')
    return filename:match(suffix .. '$') ~= nil
  end

  if pattern:match('^%*') and not pattern:match('^%*%.') then
    local suffix = pattern:sub(2):gsub('%.', '%%.')
    return filename:match(suffix .. '$') ~= nil
  end

  return filename:match('^' .. lua_pattern .. '$') ~= nil
end

---@param filename string
---@param content string
---@param bufnr number|nil Buffer number for TreeSitter parsing
---@param parser table|nil Pre-resolved parser to skip lookup
---@param parser_name string|nil Parser name for error messages
---@return ParsedVariable[]
function M.parse(filename, content, bufnr, parser, parser_name)
  -- If parser not provided, look it up (backward compatibility)
  if not parser then
    parser, parser_name = M.find_parser_for_file(filename)
    if not parser then
      return {}
    end
  end

  -- Call parser with bufnr for TreeSitter support
  local ok, result = pcall(parser.parse, content, bufnr)

  if not ok then
    vim.notify(
      string.format('[camouflage] Parser error (%s): %s', parser_name or 'unknown', result),
      vim.log.levels.WARN
    )
    return {}
  end

  return result or {}
end

---@param filename string
---@return boolean
function M.is_supported(filename)
  return M.find_parser_for_file(filename) ~= nil
end

---Clear parser cache
---@return nil
function M.clear_cache()
  parser_cache.filename = nil
  parser_cache.parser = nil
  parser_cache.parser_name = nil
end

---Register all built-in parsers
---@return nil
function M.setup()
  -- Clear cache when setup is called (config may have changed)
  M.clear_cache()
  M.parsers = {}
  M.entries = {}

  local builtins = {
    { name = 'env', module = 'camouflage.parsers.env' },
    { name = 'json', module = 'camouflage.parsers.json' },
    { name = 'yaml', module = 'camouflage.parsers.yaml' },
    { name = 'toml', module = 'camouflage.parsers.toml' },
    { name = 'properties', module = 'camouflage.parsers.properties' },
    { name = 'netrc', module = 'camouflage.parsers.netrc' },
    { name = 'xml', module = 'camouflage.parsers.xml' },
    { name = 'http', module = 'camouflage.parsers.http' },
    { name = 'hcl', module = 'camouflage.parsers.hcl' },
    { name = 'dockerfile', module = 'camouflage.parsers.dockerfile' },
  }

  for _, b in ipairs(builtins) do
    local mod = require(b.module)
    M.register({
      name = b.name,
      parser = mod,
      filetypes = mod.filetypes,
      file_patterns = mod.file_patterns,
      priority = mod.priority,
      treesitter = mod.treesitter,
      source = 'builtin',
    })
  end
end

return M
