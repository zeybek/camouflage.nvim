---@mod camouflage.yank Yank unmasked values

local M = {}

local state = require('camouflage.state')
local config = require('camouflage.config')
local core = require('camouflage.core')
local position = require('camouflage.position')
local hooks = require('camouflage.hooks')
local log = require('camouflage.log')

-- Compatibility: vim.uv exists in Neovim 0.10+, vim.loop in 0.9
local uv = vim.uv or vim.loop

-- Per-register auto-clear timers: register -> { timer = uv_timer, secret = string|nil }
local clear_timers = {}

---Validate a register name (nil means "use the configured default").
---@param register string|nil
---@return boolean
local function validate_register(register)
  if register == nil then
    return true
  end
  if type(register) == 'string' and register:match('^[a-zA-Z0-9"*+_/%-]$') then
    return true
  end
  vim.notify(
    string.format(
      '[camouflage] Invalid register "%s" (use a-z, A-Z, 0-9, ", *, +, _, - or /)',
      tostring(register)
    ),
    vim.log.levels.ERROR
  )
  return false
end

---@class YankOpts
---@field register string|nil Register to use (default from config)
---@field force_picker boolean|nil Force picker even if cursor is on variable

---Get yank configuration with defaults
---@return table
local function get_yank_config()
  local cfg = config.get()
  return vim.tbl_deep_extend('force', {
    default_register = '+',
    notify = true,
    auto_clear_seconds = 30,
    confirm = true,
    confirm_message = 'Copy value of "%s" to clipboard?',
  }, cfg.yank or {})
end

---Find the variable at or near the cursor position
---@param bufnr number|nil Buffer number (default: current)
---@return table|nil variable The variable at cursor, or nil
function M.find_variable_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local variables = state.get_variables(bufnr)
  -- Lenient: exact byte-range match, then any variable sharing the cursor row.
  return position.find_variable_at_cursor(bufnr, variables, { same_line_fallback = true })
end

---Schedule auto-clear of a register, scoped to that register so yanking a
---second secret to a different register never cancels the first one's timer.
---@param register string Register to clear
---@param seconds number Seconds to wait before clearing
---@param secret string|nil The yanked value; the register is cleared only if it
---  still holds this exact value (so a later manual yank into the register is
---  preserved). When nil, clears unconditionally (legacy 2-arg behavior).
function M.schedule_auto_clear(register, seconds, secret)
  -- Cancel only this register's existing timer.
  local existing = clear_timers[register]
  if existing then
    existing.timer:stop()
    existing.timer:close()
    clear_timers[register] = nil
  end

  if not seconds or seconds <= 0 then
    return
  end

  local timer = uv.new_timer()
  clear_timers[register] = { timer = timer, secret = secret }
  timer:start(
    seconds * 1000,
    0,
    vim.schedule_wrap(function()
      -- Only act if this timer still owns the register entry (a reschedule may
      -- have replaced us between firing and running on the main loop).
      local entry = clear_timers[register]
      if not entry or entry.timer ~= timer then
        return
      end
      clear_timers[register] = nil
      timer:close()

      if secret == nil or vim.fn.getreg(register) == secret then
        vim.fn.setreg(register, '')
        vim.notify('[camouflage] Clipboard cleared', vim.log.levels.INFO)
      end
    end)
  )
end

---Perform the actual yank operation
---@param var table Variable to yank
---@param opts YankOpts|nil Options
function M.do_yank(var, opts)
  opts = opts or {}
  local cfg = get_yank_config()
  local register = opts.register or cfg.default_register
  if not validate_register(register) then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()

  -- HOOK: before_yank
  local should_continue = hooks.emit('before_yank', bufnr, var)
  if should_continue == false then
    return
  end

  -- Copy to register
  vim.fn.setreg(register, var.value)

  -- Show notification
  if cfg.notify then
    local display_reg = register == '+' and 'clipboard' or ('register ' .. register)
    vim.notify(
      string.format('[camouflage] Copied: %s -> %s', var.key, display_reg),
      vim.log.levels.INFO
    )
  end

  -- Schedule auto-clear
  if cfg.auto_clear_seconds and cfg.auto_clear_seconds > 0 then
    M.schedule_auto_clear(register, cfg.auto_clear_seconds, var.value)
  end

  -- HOOK: after_yank
  hooks.emit('after_yank', bufnr, var, register)
end

---Show confirmation and yank if confirmed
---@param var table Variable to yank
---@param opts YankOpts|nil Options
function M.confirm_and_yank(var, opts)
  local cfg = get_yank_config()

  if cfg.confirm then
    local message = string.format(cfg.confirm_message, var.key)
    vim.ui.select({ 'Yes', 'No' }, {
      prompt = message,
    }, function(choice)
      if choice == 'Yes' then
        M.do_yank(var, opts)
      end
    end)
  else
    M.do_yank(var, opts)
  end
end

---Yank value at cursor position
---@param opts YankOpts|nil Options
---@return boolean success Whether a variable was found and yanked
function M.yank_at_cursor(opts)
  local var = M.find_variable_at_cursor()
  if not var then
    return false
  end

  M.confirm_and_yank(var, opts)
  return true
end

---Show picker with all variables and yank selected
---@param opts YankOpts|nil Options
function M.yank_with_picker(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local variables = state.get_variables(bufnr)

  if #variables == 0 then
    vim.notify('[camouflage] No masked variables in buffer', vim.log.levels.WARN)
    return
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    log.pcall_error('nvim_buf_get_lines', lines, { bufnr = bufnr })
    return
  end

  local line_offsets = core.compute_line_offsets(lines)

  -- Build picker items
  local items = {}
  for _, var in ipairs(variables) do
    local pos = core.index_to_position(bufnr, var.start_index, lines, line_offsets)
    local line_num = pos and (pos.row + 1) or '?'
    table.insert(items, {
      label = var.key,
      line = line_num,
      var = var,
    })
  end

  vim.ui.select(items, {
    prompt = 'Select variable to copy:',
    format_item = function(item)
      return string.format('%s (line %s)', item.label, item.line)
    end,
  }, function(choice)
    if choice then
      M.confirm_and_yank(choice.var, opts)
    end
  end)
end

---Main yank function (hybrid: cursor or picker)
---@param opts YankOpts|nil Options
function M.yank(opts)
  opts = opts or {}

  if not validate_register(opts.register) then
    return
  end

  -- Check if buffer has any variables
  local bufnr = vim.api.nvim_get_current_buf()
  local variables = state.get_variables(bufnr)

  if #variables == 0 then
    vim.notify('[camouflage] No masked variables in buffer', vim.log.levels.WARN)
    return
  end

  -- Force picker if requested
  if opts.force_picker then
    M.yank_with_picker(opts)
    return
  end

  -- Try cursor-based first
  local found = M.yank_at_cursor(opts)

  -- Fall back to picker if no variable at cursor
  if not found then
    M.yank_with_picker(opts)
  end
end

---Cancel all pending auto-clear timers (for testing)
---@return nil
function M.cancel_auto_clear()
  for register, entry in pairs(clear_timers) do
    entry.timer:stop()
    entry.timer:close()
    clear_timers[register] = nil
  end
end

return M
