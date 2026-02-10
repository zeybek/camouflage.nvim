---@mod camouflage.parsers Parser registry

local M = {}

---@class ParsedVariable
---@field key string
---@field value string
---@field start_index number
---@field end_index number
---@field line_number number
---@field is_nested boolean
---@field is_commented boolean

---@type table<string, table>
M.parsers = {}

-- Simple cache for find_parser_for_file to avoid repeated lookups
---@type {filename: string|nil, parser: table|nil, parser_name: string|nil}
local parser_cache = { filename = nil, parser = nil, parser_name = nil }

---@param name string
---@param parser table
function M.register(name, parser)
  M.parsers[name] = parser
end

---@param name string
---@return table|nil
function M.get(name)
  return M.parsers[name]
end

---@param filename string
---@return table|nil, string|nil
function M.find_parser_for_file(filename)
  -- Check cache first
  if parser_cache.filename == filename then
    return parser_cache.parser, parser_cache.parser_name
  end

  local config = require('camouflage.config').get()
  local basename = vim.fn.fnamemodify(filename, ':t')

  for _, pattern_config in ipairs(config.patterns) do
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

  -- Cache negative result too
  parser_cache.filename = filename
  parser_cache.parser = nil
  parser_cache.parser_name = nil
  return nil, nil
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
---@param lines string[]|nil Pre-split lines to avoid re-splitting in parsers
---@param parser table|nil Pre-resolved parser to skip lookup
---@param parser_name string|nil Parser name for error messages
---@return ParsedVariable[]
function M.parse(filename, content, lines, parser, parser_name)
  -- If parser not provided, look it up (backward compatibility)
  if not parser then
    parser, parser_name = M.find_parser_for_file(filename)
    if not parser then
      return {}
    end
  end

  -- Call parser with lines if it supports them, otherwise just content
  local ok, result
  if parser.parse_with_lines then
    ok, result = pcall(parser.parse_with_lines, content, lines)
  else
    ok, result = pcall(parser.parse, content, lines)
  end

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

function M.setup()
  M.register('env', require('camouflage.parsers.env'))
  M.register('json', require('camouflage.parsers.json'))
  M.register('yaml', require('camouflage.parsers.yaml'))
  M.register('toml', require('camouflage.parsers.toml'))
  M.register('properties', require('camouflage.parsers.properties'))
  M.register('netrc', require('camouflage.parsers.netrc'))
end

return M
