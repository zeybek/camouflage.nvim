---@mod camouflage.checks.registry Public check registry
---@brief [[
--- Runtime registry for trusted Lua checks. Registered checks inspect parsed
--- variables during masking and publish redacted results through the shared
--- checks badge store.
---@brief ]]

local M = {}

local log = require('camouflage.log')

---@class CamouflageCheckSpec
---@field name string
---@field run fun(ctx: CamouflageCheckContext, done?: fun(result: CheckResult|nil))
---@field async? boolean
---@field priority? integer
---@field default_enabled? boolean

---@class CamouflageCheckContext
---@field bufnr integer
---@field filename string
---@field parser_name string
---@field var ParsedVariable
---@field config table
---@field run_id integer
---@field check_name string

---@class CamouflageRegisteredCheck
---@field name string
---@field run fun(ctx: CamouflageCheckContext, done?: fun(result: CheckResult|nil))
---@field async boolean
---@field priority integer
---@field default_enabled boolean

---@type table<string, CamouflageRegisteredCheck>
local registry = {}

---@type table<integer, integer>
local buffer_runs = {}

local VALID_SEVERITY = { info = true, warning = true, error = true }
local ALLOWED_RESULT_FIELDS = {
  severity = true,
  text = true,
  hl_group = true,
  sign_text = true,
  sign_hl = true,
  line_hl = true,
  priority = true,
  data = true,
}

---@param name string
---@return boolean
local function valid_name(name)
  return type(name) == 'string' and name:match('^%a[%w_%-]*$') ~= nil and #name <= 64
end

---@param msg string
local function reject(msg)
  error('[camouflage] ' .. msg, 3)
end

---@param value any
---@return boolean
local function is_integer(value)
  return type(value) == 'number' and value % 1 == 0
end

---@param bufnr integer
---@return integer
local function next_run_id(bufnr)
  local run_id = (buffer_runs[bufnr] or 0) + 1
  buffer_runs[bufnr] = run_id
  return run_id
end

---@param value any
---@param secret string
---@param seen table<table, boolean>
---@return boolean
local function contains_secret(value, secret, seen)
  if secret == '' then
    return false
  end

  local value_type = type(value)
  if value_type == 'string' then
    return value:find(secret, 1, true) ~= nil
  end
  if value_type ~= 'table' then
    return false
  end
  if seen[value] then
    return false
  end
  seen[value] = true

  for k, v in pairs(value) do
    if contains_secret(k, secret, seen) or contains_secret(v, secret, seen) then
      return true
    end
  end
  return false
end

---@param value any
---@param seen table<table, boolean>
---@return boolean
local function is_data_only(value, seen)
  local value_type = type(value)
  if
    value == nil
    or value_type == 'string'
    or value_type == 'number'
    or value_type == 'boolean'
  then
    return true
  end
  if value_type ~= 'table' then
    return false
  end
  if seen[value] then
    return true
  end
  seen[value] = true

  for k, v in pairs(value) do
    local key_type = type(k)
    if key_type ~= 'string' and key_type ~= 'number' then
      return false
    end
    if not is_data_only(v, seen) then
      return false
    end
  end
  return true
end

---@param check_name string
---@param msg string
local function debug_drop(check_name, msg)
  log.debug('check %s result dropped: %s', check_name, msg)
end

---@param err any
---@param ctx CamouflageCheckContext
---@return string
local function redacted_error(err, ctx)
  local message = tostring(err)
  local value = ctx.var and ctx.var.value
  if type(value) == 'string' and value ~= '' then
    message = message:gsub(vim.pesc(value), '[redacted]')
  end
  return message
end

---@param result any
---@param ctx CamouflageCheckContext
---@return CheckResult|nil
local function normalize_result(result, ctx)
  if result == nil then
    return nil
  end
  if type(result) ~= 'table' then
    debug_drop(ctx.check_name, 'result is not a table')
    return nil
  end
  if not VALID_SEVERITY[result.severity] then
    debug_drop(ctx.check_name, 'severity must be info, warning, or error')
    return nil
  end

  local normalized = {}
  for key, _ in pairs(ALLOWED_RESULT_FIELDS) do
    normalized[key] = result[key]
  end

  if normalized.text ~= nil and type(normalized.text) ~= 'string' then
    debug_drop(ctx.check_name, 'text must be a string')
    return nil
  end
  if normalized.hl_group ~= nil and type(normalized.hl_group) ~= 'string' then
    debug_drop(ctx.check_name, 'hl_group must be a string')
    return nil
  end
  if normalized.sign_text ~= nil and type(normalized.sign_text) ~= 'string' then
    debug_drop(ctx.check_name, 'sign_text must be a string')
    return nil
  end
  if normalized.sign_hl ~= nil and type(normalized.sign_hl) ~= 'string' then
    debug_drop(ctx.check_name, 'sign_hl must be a string')
    return nil
  end
  if normalized.line_hl ~= nil and type(normalized.line_hl) ~= 'string' then
    debug_drop(ctx.check_name, 'line_hl must be a string')
    return nil
  end
  if normalized.priority ~= nil and not is_integer(normalized.priority) then
    debug_drop(ctx.check_name, 'priority must be an integer')
    return nil
  end
  if normalized.data ~= nil then
    if type(normalized.data) ~= 'table' then
      debug_drop(ctx.check_name, 'data must be a table')
      return nil
    end
    if not is_data_only(normalized.data, {}) then
      debug_drop(ctx.check_name, 'data must contain only primitive values and tables')
      return nil
    end
  end

  local value = ctx.var and ctx.var.value
  if type(value) == 'string' and value ~= '' then
    if normalized.text and normalized.text:find(value, 1, true) then
      debug_drop(ctx.check_name, 'text contains the variable value')
      return nil
    end
    if normalized.data and contains_secret(normalized.data, value, {}) then
      debug_drop(ctx.check_name, 'data contains the variable value')
      return nil
    end
  end

  if normalized.data then
    normalized.data = vim.deepcopy(normalized.data)
  end
  return normalized
end

---@param entry CamouflageRegisteredCheck
---@return CamouflageRegisteredCheck
local function public_entry(entry)
  return {
    name = entry.name,
    run = entry.run,
    async = entry.async,
    priority = entry.priority,
    default_enabled = entry.default_enabled,
  }
end

---@param cfg table|nil
---@param entry CamouflageRegisteredCheck
---@return table
---@return boolean
local function check_config(cfg, entry)
  local checks_cfg = (cfg and cfg.checks) or {}
  local check_cfg = checks_cfg[entry.name] or {}
  if type(check_cfg) ~= 'table' then
    check_cfg = {}
  end

  local enabled = entry.default_enabled ~= false
  if check_cfg.enabled ~= nil then
    enabled = check_cfg.enabled ~= false
  end
  return check_cfg, enabled
end

---@param entries CamouflageRegisteredCheck[]
---@return CamouflageRegisteredCheck[]
local function sort_entries(entries)
  table.sort(entries, function(a, b)
    if a.priority ~= b.priority then
      return a.priority > b.priority
    end
    return a.name < b.name
  end)
  return entries
end

---@return CamouflageRegisteredCheck[]
local function sorted_entries()
  local entries = {}
  for _, entry in pairs(registry) do
    table.insert(entries, entry)
  end
  return sort_entries(entries)
end

---@param bufnr integer
local function clear_registered_results(bufnr)
  local ok, checks = pcall(require, 'camouflage.checks')
  if not ok then
    return
  end

  for name, _ in pairs(registry) do
    checks.clear_check(bufnr, name)
  end
end

---@param bufnr integer
---@param entry CamouflageRegisteredCheck
---@param ctx CamouflageCheckContext
---@return boolean
local function still_current(bufnr, entry, ctx)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if registry[entry.name] ~= entry then
    return false
  end
  if buffer_runs[bufnr] ~= ctx.run_id then
    return false
  end
  if ctx.changedtick ~= vim.api.nvim_buf_get_changedtick(bufnr) then
    return false
  end

  local ok, state = pcall(require, 'camouflage.state')
  if not ok then
    return false
  end
  for _, var in ipairs(state.get_variables(bufnr) or {}) do
    if
      var.line_number == ctx.var.line_number
      and var.start_index == ctx.var.start_index
      and var.end_index == ctx.var.end_index
      and var.key == ctx.var.key
      and var.value == ctx.var.value
    then
      return true
    end
  end
  return false
end

---@param bufnr integer
---@param entry CamouflageRegisteredCheck
---@param ctx CamouflageCheckContext
---@param result any
local function publish_result(bufnr, entry, ctx, result)
  if not still_current(bufnr, entry, ctx) then
    log.debug('check %s async result ignored for stale run %d', entry.name, ctx.run_id)
    return
  end

  local normalized = normalize_result(result, ctx)
  if normalized == nil then
    return
  end

  require('camouflage.checks').set_result(bufnr, ctx.var.line_number, entry.name, normalized)
end

---@param entry CamouflageRegisteredCheck
---@param ctx CamouflageCheckContext
local function run_sync(entry, ctx)
  local start = (vim.uv or vim.loop).hrtime()
  local ok, result = pcall(entry.run, ctx)
  local elapsed_ms = ((vim.uv or vim.loop).hrtime() - start) / 1000000
  if not ok then
    log.debug('check %s failed in %.2fms: %s', entry.name, elapsed_ms, redacted_error(result, ctx))
    return
  end
  log.debug('check %s completed in %.2fms', entry.name, elapsed_ms)

  local normalized = normalize_result(result, ctx)
  if normalized == nil then
    return
  end
  require('camouflage.checks').set_result(ctx.bufnr, ctx.var.line_number, entry.name, normalized)
end

---@param entry CamouflageRegisteredCheck
---@param ctx CamouflageCheckContext
local function run_async(entry, ctx)
  local start = (vim.uv or vim.loop).hrtime()
  local done_called = false
  local done = vim.schedule_wrap(function(result)
    local elapsed_ms = ((vim.uv or vim.loop).hrtime() - start) / 1000000
    if done_called then
      log.debug('check %s ignored duplicate async completion in %.2fms', entry.name, elapsed_ms)
      return
    end
    done_called = true
    log.debug('check %s async completed in %.2fms', entry.name, elapsed_ms)
    publish_result(ctx.bufnr, entry, ctx, result)
  end)

  local ok, err = pcall(entry.run, ctx, done)
  if not ok then
    log.debug('check %s failed to start async run: %s', entry.name, redacted_error(err, ctx))
  end
end

---Register a public check.
---@param spec CamouflageCheckSpec
---@return CamouflageRegisteredCheck
function M.register(spec)
  if type(spec) ~= 'table' then
    reject('register_check requires a spec table')
  end
  if not valid_name(spec.name) then
    reject('register_check requires a valid name')
  end
  if registry[spec.name] then
    reject(string.format('check "%s" is already registered', spec.name))
  end
  if type(spec.run) ~= 'function' then
    reject('register_check requires a run function')
  end
  if spec.async ~= nil and type(spec.async) ~= 'boolean' then
    reject('register_check async must be a boolean')
  end
  if spec.default_enabled ~= nil and type(spec.default_enabled) ~= 'boolean' then
    reject('register_check default_enabled must be a boolean')
  end
  if spec.priority ~= nil and not is_integer(spec.priority) then
    reject('register_check priority must be an integer')
  end

  local entry = {
    name = spec.name,
    run = spec.run,
    async = spec.async == true,
    priority = spec.priority or 50,
    default_enabled = spec.default_enabled ~= false,
  }
  registry[entry.name] = entry
  log.debug('registered check %s async=%s priority=%d', entry.name, entry.async, entry.priority)
  return public_entry(entry)
end

---Unregister a check and clear its rendered results from loaded buffers.
---@param name string
---@return boolean removed
function M.unregister(name)
  if type(name) ~= 'string' or not registry[name] then
    return false
  end
  registry[name] = nil

  local ok, checks = pcall(require, 'camouflage.checks')
  if ok then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      checks.clear_check(bufnr, name)
    end
  end
  log.debug('unregistered check %s', name)
  return true
end

---List registered checks sorted by priority descending, then name.
---@return CamouflageRegisteredCheck[]
function M.list()
  local entries = {}
  for _, entry in ipairs(sorted_entries()) do
    table.insert(entries, public_entry(entry))
  end
  return entries
end

---Get a registered check by name.
---@param name string
---@return CamouflageRegisteredCheck|nil
function M.get(name)
  local entry = registry[name]
  return entry and public_entry(entry) or nil
end

---Start a new decoration pass for registered checks.
---@param bufnr integer
---@return integer run_id
function M.begin_decorate(bufnr)
  local run_id = next_run_id(bufnr)
  clear_registered_results(bufnr)
  return run_id
end

---Run enabled registered checks for parsed variables.
---@param opts { bufnr: integer, filename: string, parser_name: string, variables: ParsedVariable[], config: table, run_id?: integer }
function M.run(opts)
  if not opts or type(opts) ~= 'table' then
    return
  end
  local bufnr = opts.bufnr
  if type(bufnr) ~= 'number' or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local entries = sorted_entries()
  if #entries == 0 then
    return
  end

  local run_id = opts.run_id or next_run_id(bufnr)
  buffer_runs[bufnr] = run_id
  local variables = opts.variables or {}
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  log.debug(
    'running %d registered checks for %d variables in buffer %d run %d',
    #entries,
    #variables,
    bufnr,
    run_id
  )

  for _, var in ipairs(variables) do
    for _, entry in ipairs(entries) do
      local check_cfg, enabled = check_config(opts.config, entry)
      if enabled then
        local ctx = {
          bufnr = bufnr,
          filename = opts.filename,
          parser_name = opts.parser_name,
          var = var,
          config = check_cfg,
          run_id = run_id,
          check_name = entry.name,
          changedtick = changedtick,
        }
        if entry.async then
          run_async(entry, ctx)
        else
          run_sync(entry, ctx)
        end
      end
    end
  end
end

---Internal: reset registry state for tests.
function M._reset()
  registry = {}
  buffer_runs = {}
end

---Internal: expose result validation for focused tests.
M._normalize_result = normalize_result

return M
