---@mod camouflage.hooks Event System / Hooks
---@brief [[
--- Provides an event system for extending camouflage behavior.
--- Supports both config-based hooks and dynamic listener registration.
---
--- Events:
---   - before_decorate: Fired before decorations are applied
---   - variable_detected: Fired for each detected variable (can filter)
---   - after_decorate: Fired after all decorations are applied
---   - before_reveal / after_reveal: Fired on line reveal
---   - before_yank / after_yank: Fired on value yank
---   - before_follow_start / after_follow_start: Fired when follow cursor mode starts
---   - before_follow_stop / after_follow_stop: Fired when follow cursor mode stops
---
--- Usage:
---   -- Config-based (in setup)
---   require('camouflage').setup({
---     hooks = {
---       on_variable_detected = function(bufnr, var)
---         return var.key:match('PASSWORD') -- only mask PASSWORD keys
---       end,
---     }
---   })
---
---   -- Dynamic registration
---   local id = require('camouflage').on('variable_detected', function(bufnr, var)
---     return var.key:match('SECRET')
---   end)
---   require('camouflage').off('variable_detected', id)
---@brief ]]

local M = {}

-- Event types
M.EVENTS = {
  BEFORE_DECORATE = 'before_decorate',
  VARIABLE_DETECTED = 'variable_detected',
  AFTER_DECORATE = 'after_decorate',
  BEFORE_YANK = 'before_yank',
  AFTER_YANK = 'after_yank',
  BEFORE_REVEAL = 'before_reveal',
  AFTER_REVEAL = 'after_reveal',
  BEFORE_FOLLOW_START = 'before_follow_start',
  AFTER_FOLLOW_START = 'after_follow_start',
  BEFORE_FOLLOW_STOP = 'before_follow_stop',
  AFTER_FOLLOW_STOP = 'after_follow_stop',
}

---Build an allowlisted, value-free copy of detected variables for the public
---User autocmd payload. Allowlist (copy known-safe fields) rather than blocklist
---(strip value) so any future ParsedVariable field is private by default — only
---in-process Lua listeners (hooks.on / config hooks) ever see plaintext values.
---@param variables table[]|any
---@return table[]|any
local function redact_variables(variables)
  if type(variables) ~= 'table' then
    return variables
  end
  local out = {}
  for i, var in ipairs(variables) do
    out[i] = {
      key = var.key,
      start_index = var.start_index,
      end_index = var.end_index,
      line_number = var.line_number,
      is_nested = var.is_nested,
      is_commented = var.is_commented,
      is_multiline = var.is_multiline,
      value_length = type(var.value) == 'string' and #var.value or nil,
    }
  end
  return out
end

-- User autocmd specs, keyed by event. Each builds its own payload from the
-- emit() arguments, so before_decorate (bufnr, filename) and after_decorate
-- (bufnr, variables) no longer share one mislabeled shape.
-- variable_detected is intentionally absent (too frequent).
local AUTOCMD_EVENTS = {
  before_decorate = {
    pattern = 'CamouflageBeforeDecorate',
    payload = function(bufnr, filename)
      return { bufnr = bufnr, filename = filename }
    end,
  },
  after_decorate = {
    pattern = 'CamouflageAfterDecorate',
    payload = function(bufnr, variables)
      local filename = (bufnr and vim.api.nvim_buf_is_valid(bufnr))
          and vim.api.nvim_buf_get_name(bufnr)
        or nil
      return { bufnr = bufnr, filename = filename, variables = redact_variables(variables) }
    end,
  },
}

---@class CamouflageListener
---@field id number Unique listener ID
---@field callback function Callback function

---@type table<string, CamouflageListener[]>
local listeners = {}

---@type number
local next_id = 1

---@type CamouflageHooksConfig|nil
local config_hooks = nil

---Initialize hooks with config
---@param hooks CamouflageHooksConfig|nil
function M.setup(hooks)
  config_hooks = hooks or {}
end

---Register an event listener
---@param event string Event name (before_decorate, variable_detected, after_decorate)
---@param callback function Callback function
---@return number id Listener ID for unregistration
function M.on(event, callback)
  if not listeners[event] then
    listeners[event] = {}
  end

  local id = next_id
  next_id = next_id + 1

  table.insert(listeners[event], {
    id = id,
    callback = callback,
  })

  return id
end

---Register a one-time event listener
---@param event string Event name
---@param callback function Callback function
---@return number id Listener ID
function M.once(event, callback)
  local id
  id = M.on(event, function(...)
    M.off(event, id)
    return callback(...)
  end)
  return id
end

---Unregister an event listener
---@param event string Event name
---@param id number Listener ID returned from on()
---@return boolean success Whether the listener was found and removed
function M.off(event, id)
  if not listeners[event] then
    return false
  end

  for i, listener in ipairs(listeners[event]) do
    if listener.id == id then
      table.remove(listeners[event], i)
      return true
    end
  end

  return false
end

---Get all registered listeners for an event
---@param event string Event name
---@return CamouflageListener[]
function M.list(event)
  return listeners[event] or {}
end

---Clear all listeners for an event (or all events if nil)
---@param event string|nil Event name or nil for all
function M.clear(event)
  if event then
    listeners[event] = {}
  else
    listeners = {}
  end
end

---Emit an event and call all handlers
---@param event string Event name
---@param ... any Event arguments
---@return boolean|nil result Combined result for filter events
function M.emit(event, ...)
  local results = {}

  -- 1. Call config hook first (if exists)
  if config_hooks then
    local hook_name = 'on_' .. event
    local hook = config_hooks[hook_name]
    if hook and type(hook) == 'function' then
      local ok, result = pcall(hook, ...)
      if ok then
        table.insert(results, result)
      else
        vim.notify(
          string.format('[camouflage] Hook error (%s): %s', hook_name, result),
          vim.log.levels.WARN
        )
      end
    end
  end

  -- 2. Call all registered listeners.
  -- Iterate a shallow snapshot so a listener that removes itself (once) or
  -- another listener (off) mid-dispatch cannot shift the array and skip the
  -- next listener. Every listener present at emit start runs exactly once.
  local current = listeners[event]
  if current then
    local snapshot = {}
    for i = 1, #current do
      snapshot[i] = current[i]
    end
    for _, listener in ipairs(snapshot) do
      local ok, result = pcall(listener.callback, ...)
      if ok then
        table.insert(results, result)
      else
        vim.notify(
          string.format('[camouflage] Listener error (%s#%d): %s', event, listener.id, result),
          vim.log.levels.WARN
        )
      end
    end
  end

  -- 3. Fire the public User autocmd (before_decorate / after_decorate only).
  -- The payload carries keys + byte positions + value_length but never the
  -- plaintext values, so listening plugins cannot harvest secrets.
  local autocmd_spec = AUTOCMD_EVENTS[event]
  if autocmd_spec then
    vim.api.nvim_exec_autocmds('User', {
      pattern = autocmd_spec.pattern,
      data = autocmd_spec.payload(...),
    })
  end

  -- 4. Determine combined result for filter events
  -- For variable_detected: if ANY returns false, skip the variable
  -- For before_decorate: if ANY returns false, cancel decoration
  for _, result in ipairs(results) do
    if result == false then
      return false
    end
  end

  -- All returned true or nil
  if #results > 0 then
    return true
  end

  return nil
end

---Check if any listeners are registered for an event
---@param event string Event name
---@return boolean
function M.has_listeners(event)
  if config_hooks and config_hooks['on_' .. event] then
    if type(config_hooks['on_' .. event]) == 'function' then
      return true
    end
  end

  if listeners[event] and #listeners[event] > 0 then
    return true
  end

  return false
end

return M
