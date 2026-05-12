---@mod camouflage.checks.expiry JWT expiry hint check
---@brief [[
--- Detects JWT tokens among parsed values, decodes their `exp` claim,
--- and emits a check result via camouflage.checks.set_result. The
--- badges renderer composes the result into the end-of-line virtual
--- text on the same line.
---@brief ]]

local M = {}

local checks = require('camouflage.checks')
local config_mod = require('camouflage.config')
local hooks = require('camouflage.hooks')
local jwt = require('camouflage.checks.expiry.jwt')
local log = require('camouflage.log')

local CHECK_NAME = 'expiry'

---@type integer|nil
local listener_id_before = nil
---@type integer|nil
local listener_id_variable = nil

---@type table<integer, uv.uv_timer_t>
local auto_timers = {}

---@return CamouflageExpiryConfig
local function get_config()
  local cfg = config_mod.get()
  return (cfg.checks and cfg.checks.expiry) or {}
end

---Format a number of seconds as a short human duration.
---@param seconds integer
---@return string
local function format_duration(seconds)
  seconds = math.abs(seconds)
  if seconds < 60 then
    return seconds .. 's'
  elseif seconds < 3600 then
    return math.floor(seconds / 60) .. 'm'
  elseif seconds < 86400 then
    return math.floor(seconds / 3600) .. 'h'
  else
    return math.floor(seconds / 86400) .. 'd'
  end
end

---Classify remaining seconds against config thresholds.
---@param remaining integer
---@param cfg CamouflageExpiryConfig
---@return string|nil status one of 'valid' | 'warning' | 'expired', or nil to suppress
---@return string severity 'info' | 'warning' | 'error'
---@return string hl
local function classify(remaining, cfg)
  local show_th = cfg.show_threshold_seconds or 86400
  local warn_th = cfg.warn_threshold_seconds or 3600

  if remaining <= 0 then
    return 'expired', 'error', cfg.hl_expired or 'DiagnosticError'
  elseif remaining < warn_th then
    return 'warning', 'warning', cfg.hl_warning or 'DiagnosticWarn'
  elseif remaining < show_th then
    return 'valid', 'info', cfg.hl_valid or 'Comment'
  end
  return nil, 'info', cfg.hl_valid or 'Comment'
end

---Build the badge text for a token given its classification.
---@param status string
---@param remaining integer
---@param provider string|nil
---@return string
local function format_text(status, remaining, provider)
  local body
  if status == 'expired' then
    body = 'expired ' .. format_duration(remaining) .. ' ago'
  elseif status == 'warning' then
    body = 'expires in ' .. format_duration(remaining)
  else -- valid
    body = 'valid ' .. format_duration(remaining)
  end
  if provider and #provider > 0 then
    return string.format('[%s %s]', provider, body)
  end
  return '[' .. body .. ']'
end

---Inspect a single parsed variable and write/clear an expiry result.
---@param bufnr integer
---@param var ParsedVariable
local function inspect_variable(bufnr, var)
  if not var or type(var.value) ~= 'string' then
    return
  end

  local token = jwt.decode(var.value)
  if not token then
    return
  end

  local cfg = get_config()
  local exp = token.claims.exp
  if type(exp) ~= 'number' then
    return
  end

  local remaining = exp - os.time()
  local status, severity, hl = classify(math.floor(remaining), cfg)
  if not status then
    return
  end

  local provider = cfg.show_provider ~= false and jwt.provider_name(token.claims.iss) or nil

  checks.set_result(bufnr, var.line_number, CHECK_NAME, {
    severity = severity,
    text = format_text(status, math.floor(remaining), provider),
    hl_group = hl,
    priority = 50,
    data = { exp = exp, iss = token.claims.iss, status = status },
  })
end

---Re-render all existing expiry badges in a buffer based on the current
---wall-clock (no re-decoding — the exp value is stored in result.data).
---@param bufnr integer
function M.refresh_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local cfg = get_config()
  local now = os.time()

  for _, lnum in ipairs(checks.store.lines_with_results(bufnr)) do
    local existing = checks.store.get(bufnr, lnum, CHECK_NAME)
    if existing and existing.data and existing.data.exp then
      local remaining = math.floor(existing.data.exp - now)
      local status, severity, hl = classify(remaining, cfg)
      if status then
        local provider = cfg.show_provider ~= false and jwt.provider_name(existing.data.iss) or nil
        checks.set_result(bufnr, lnum, CHECK_NAME, {
          severity = severity,
          text = format_text(status, remaining, provider),
          hl_group = hl,
          priority = 50,
          data = existing.data,
        })
      else
        checks.set_result(bufnr, lnum, CHECK_NAME, nil)
      end
    end
  end
end

---Run a full expiry check on a buffer by re-walking the latest parsed
---variables held in state.
---@param bufnr integer
function M.check_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local state = require('camouflage.state')
  -- Clear existing expiry results first so removed JWTs disappear.
  checks.clear_check(bufnr, CHECK_NAME)
  for _, var in ipairs(state.get_variables(bufnr) or {}) do
    inspect_variable(bufnr, var)
  end
end

---Start a background timer that periodically refreshes expiry text so
---'expires in 2h' becomes 'expires in 1h59m' without user action.
---@param bufnr integer
local function start_auto_refresh(bufnr)
  local cfg = get_config()
  local interval = (cfg.refresh or {}).auto_interval or 0
  if not interval or interval <= 0 then
    return
  end
  if auto_timers[bufnr] then
    return
  end
  local timer = (vim.uv or vim.loop).new_timer()
  if not timer then
    return
  end
  auto_timers[bufnr] = timer
  timer:start(
    interval * 1000,
    interval * 1000,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        M.stop_auto_refresh(bufnr)
        return
      end
      M.refresh_buffer(bufnr)
    end)
  )
end

---@param bufnr integer
function M.stop_auto_refresh(bufnr)
  local timer = auto_timers[bufnr]
  if timer then
    pcall(function()
      timer:stop()
      timer:close()
    end)
    auto_timers[bufnr] = nil
  end
end

---@return boolean
function M.is_enabled()
  local cfg = get_config()
  return cfg.enabled ~= false
end

---Hook into the variable_detected / before_decorate events so expiry
---runs as part of the regular decoration pipeline.
function M.setup()
  if not M.is_enabled() then
    return
  end

  -- Clean slate at the start of each decoration cycle so stale results
  -- (lines that no longer hold a JWT) disappear.
  if listener_id_before then
    pcall(hooks.off, 'before_decorate', listener_id_before)
  end
  listener_id_before = hooks.on('before_decorate', function(bufnr, _filename)
    if M.is_enabled() then
      checks.clear_check(bufnr, CHECK_NAME)
    end
  end)

  if listener_id_variable then
    pcall(hooks.off, 'variable_detected', listener_id_variable)
  end
  listener_id_variable = hooks.on('variable_detected', function(bufnr, var)
    if not M.is_enabled() then
      return
    end
    local ok, err = pcall(inspect_variable, bufnr, var)
    if not ok then
      log.debug('expiry inspect_variable error: %s', err)
    end
    -- Do not return a value — variable_detected uses returns to filter masking.
  end)
end

---Tear down all timers and listeners (used on disable/reload).
function M.teardown()
  for bufnr, _ in pairs(auto_timers) do
    M.stop_auto_refresh(bufnr)
  end
  if listener_id_before then
    pcall(hooks.off, 'before_decorate', listener_id_before)
    listener_id_before = nil
  end
  if listener_id_variable then
    pcall(hooks.off, 'variable_detected', listener_id_variable)
    listener_id_variable = nil
  end
end

---Public: start auto-refresh timer for a buffer.
M.start_auto_refresh = start_auto_refresh

return M
