---@mod camouflage.log Logging utilities
---@brief [[
--- Provides logging functionality with multiple log levels.
--- Debug/trace logs only appear when config.debug = true.
--- Warn/error logs always appear.
---@brief ]]

local M = {}

---Log levels matching vim.log.levels
M.levels = {
  TRACE = vim.log.levels.TRACE,
  DEBUG = vim.log.levels.DEBUG,
  INFO = vim.log.levels.INFO,
  WARN = vim.log.levels.WARN,
  ERROR = vim.log.levels.ERROR,
}

---Level names for display
local level_names = {
  [vim.log.levels.TRACE] = 'TRACE',
  [vim.log.levels.DEBUG] = 'DEBUG',
  [vim.log.levels.INFO] = 'INFO',
  [vim.log.levels.WARN] = 'WARN',
  [vim.log.levels.ERROR] = 'ERROR',
}

---Check if debug mode is enabled
---@return boolean
local function is_debug_enabled()
  -- Use pcall to avoid circular dependency during initialization
  local ok, config = pcall(require, 'camouflage.config')
  if not ok then
    return false
  end
  local cfg = config.get()
  return cfg and cfg.debug or false
end

---Log a message at the specified level
---@param level number Log level from vim.log.levels
---@param msg string Message to log (can contain format specifiers)
---@param ... any Format arguments
---@return nil
local function log(level, msg, ...)
  -- Skip debug/trace/info logs if debug mode is disabled
  if level < vim.log.levels.WARN and not is_debug_enabled() then
    return
  end

  -- Format message if arguments provided
  local formatted = msg
  local nargs = select('#', ...)
  if nargs > 0 then
    local args = { ... }
    -- Safely format, handling nil values (use numeric loop, not ipairs which stops at nil)
    for i = 1, nargs do
      local arg = args[i]
      if arg == nil then
        args[i] = 'nil'
      elseif type(arg) == 'table' then
        args[i] = vim.inspect(arg)
      end
    end
    ---@diagnostic disable-next-line: deprecated
    local ok, result = pcall(string.format, msg, unpack(args, 1, nargs))
    if ok then
      formatted = result
    else
      -- Fallback: concatenate all arguments
      local parts = {}
      for i = 1, nargs do
        parts[i] = tostring(args[i])
      end
      formatted = msg .. ' ' .. table.concat(parts, ' ')
    end
  end

  -- Build prefix with level name
  local level_name = level_names[level] or 'UNKNOWN'
  local prefix = string.format('[camouflage:%s]', level_name)

  vim.notify(prefix .. ' ' .. formatted, level)
end

---Log a trace message (only shown when debug=true)
---@param msg string Message to log
---@param ... any Format arguments
---@return nil
function M.trace(msg, ...)
  log(M.levels.TRACE, msg, ...)
end

---Log a debug message (only shown when debug=true)
---@param msg string Message to log
---@param ... any Format arguments
---@return nil
function M.debug(msg, ...)
  log(M.levels.DEBUG, msg, ...)
end

---Log an info message (only shown when debug=true)
---@param msg string Message to log
---@param ... any Format arguments
---@return nil
function M.info(msg, ...)
  log(M.levels.INFO, msg, ...)
end

---Log a warning message (always shown)
---@param msg string Message to log
---@param ... any Format arguments
---@return nil
function M.warn(msg, ...)
  log(M.levels.WARN, msg, ...)
end

---Log an error message (always shown)
---@param msg string Message to log
---@param ... any Format arguments
---@return nil
function M.error(msg, ...)
  log(M.levels.ERROR, msg, ...)
end

---Log a table/object with a label (only shown when debug=true)
---@param label string Label for the object
---@param obj any Object to inspect
---@return nil
function M.inspect(label, obj)
  M.debug('%s: %s', label, vim.inspect(obj))
end

---Log a pcall error if debug mode is enabled
---@param operation string Name of the operation that failed
---@param err any Error message from pcall
---@param context? table Additional context (e.g., {bufnr = 1, line = 5})
---@return nil
function M.pcall_error(operation, err, context)
  local msg = operation .. ' failed'
  if context then
    local ctx_parts = {}
    for k, v in pairs(context) do
      table.insert(ctx_parts, string.format('%s=%s', k, tostring(v)))
    end
    if #ctx_parts > 0 then
      msg = msg .. ' (' .. table.concat(ctx_parts, ', ') .. ')'
    end
  end
  msg = msg .. ': ' .. tostring(err)
  M.debug(msg)
end

return M
