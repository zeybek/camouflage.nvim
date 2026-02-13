---@mod camouflage.project_config Repo-level project config loader

local M = {}

local DEFAULT_FILENAME = '.camouflage.yaml'

---@class CamouflageProjectConfigStatus
---@field loaded boolean
---@field path string|nil
---@field errors string[]

---@type CamouflageProjectConfigStatus
local state = {
  loaded = false,
  path = nil,
  errors = {},
}

---@param s string
---@return string
local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

---@param raw string
---@return any
local function parse_scalar(raw)
  local value = trim(raw)

  if value == 'true' then
    return true
  end
  if value == 'false' then
    return false
  end

  local as_number = tonumber(value)
  if as_number ~= nil then
    return as_number
  end

  if value:match('^".*"$') or value:match("^'.*'$") then
    return value:sub(2, -2)
  end

  if value:match('^%[.*%]$') then
    local body = trim(value:sub(2, -2))
    if body == '' then
      return {}
    end
    local items = {}
    for part in body:gmatch('[^,]+') do
      table.insert(items, parse_scalar(part))
    end
    return items
  end

  return value
end

---@param content string
---@return boolean, table|string
local function fallback_yaml_decode(content)
  local root = {}
  local stack = { { indent = -1, value = root } }

  for _, raw_line in ipairs(vim.split(content, '\n', { plain = true })) do
    if raw_line:match('^%s*$') or raw_line:match('^%s*#') then
      goto continue
    end

    local indent = #(raw_line:match('^(%s*)') or '')
    local line = trim(raw_line)

    while #stack > 1 and indent <= stack[#stack].indent do
      table.remove(stack)
    end

    local key, rest = line:match('^([^:]+):%s*(.*)$')
    if not key then
      return false, 'invalid YAML line: ' .. line
    end

    key = trim(key)
    local parent = stack[#stack].value
    if rest == '' then
      local child = {}
      parent[key] = child
      table.insert(stack, { indent = indent, value = child })
    else
      parent[key] = parse_scalar(rest)
    end

    ::continue::
  end

  return true, root
end

---@param msg string
local function add_error(msg)
  table.insert(state.errors, msg)
end

---@param notify_enabled boolean
local function maybe_notify_errors(notify_enabled)
  if not notify_enabled or #state.errors == 0 then
    return
  end
  vim.notify('[camouflage] project config: ' .. state.errors[#state.errors], vim.log.levels.WARN)
end

---@param filename string
---@return string|nil
local function find_project_config_file(filename)
  local found = vim.fn.findfile(filename, '.;')
  if found == '' then
    return nil
  end
  return vim.fn.fnamemodify(found, ':p')
end

---@param value any
---@param default_value any
---@param key string
---@return boolean
local function has_compatible_type(value, default_value, key)
  local default_type = type(default_value)
  local value_type = type(value)

  -- nil defaults represent "optional/any" fields
  if default_type == 'nil' then
    return true
  end

  if default_type ~= value_type then
    add_error(
      string.format(
        'type mismatch for key "%s" (expected %s, got %s)',
        key,
        default_type,
        value_type
      )
    )
    return false
  end

  return true
end

---Load and validate a repo-level project config file.
---Returns a table suitable for deep-merging into user config.
---@param opts? { enabled?: boolean, filename?: string, notify?: boolean }
---@return table
function M.load(opts)
  opts = opts or {}
  state.loaded = false
  state.path = nil
  state.errors = {}

  if opts.enabled == false then
    return {}
  end

  local filename = opts.filename or DEFAULT_FILENAME
  local path = find_project_config_file(filename)
  if not path then
    return {}
  end

  state.path = path

  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read or type(lines) ~= 'table' then
    add_error('failed to read project config file')
    maybe_notify_errors(opts.notify ~= false)
    return {}
  end

  local content = table.concat(lines, '\n')
  local ok_decode, decoded
  if vim.fn.exists('*yaml_decode') == 1 then
    ok_decode, decoded = pcall(vim.fn.yaml_decode, content)
  else
    ok_decode, decoded = fallback_yaml_decode(content)
  end

  if not ok_decode or type(decoded) ~= 'table' then
    add_error('invalid YAML in project config file')
    maybe_notify_errors(opts.notify ~= false)
    return {}
  end

  if decoded.version ~= 1 then
    add_error('unsupported project config version (expected 1)')
    maybe_notify_errors(opts.notify ~= false)
    return {}
  end

  local defaults = require('camouflage.config').defaults
  local sanitized = {}

  for key, value in pairs(decoded) do
    if key ~= 'version' then
      if key == 'project_config' then
        add_error('key "project_config" is reserved and cannot be set in project config file')
      elseif defaults[key] == nil then
        add_error(string.format('unknown project config key "%s"', key))
      elseif has_compatible_type(value, defaults[key], key) then
        sanitized[key] = value
      end
    end
  end

  state.loaded = true
  maybe_notify_errors(opts.notify ~= false)
  return sanitized
end

---@return CamouflageProjectConfigStatus
function M.status()
  return {
    loaded = state.loaded,
    path = state.path,
    errors = vim.deepcopy(state.errors),
  }
end

return M
