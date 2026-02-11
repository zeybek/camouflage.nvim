---@mod camouflage.yank Yank unmasked values

local M = {}

local state = require('camouflage.state')
local config = require('camouflage.config')
local core = require('camouflage.core')
local hooks = require('camouflage.hooks')

local clear_timer = nil

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

  if #variables == 0 then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1] - 1 -- Convert to 0-indexed
  local cursor_col = cursor[2]

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return nil
  end

  local line_offsets = core.compute_line_offsets(lines)
  local cursor_byte = line_offsets[cursor_row + 1] + cursor_col

  -- First pass: exact match (cursor within value range)
  for _, var in ipairs(variables) do
    if cursor_byte >= var.start_index and cursor_byte <= var.end_index then
      return var
    end
  end

  -- Second pass: same line match (more lenient)
  for _, var in ipairs(variables) do
    local var_pos = core.index_to_position(bufnr, var.start_index, lines, line_offsets)
    if var_pos and var_pos.row == cursor_row then
      return var
    end
  end

  return nil
end

---Schedule auto-clear of clipboard
---@param register string Register to clear
---@param seconds number Seconds to wait before clearing
function M.schedule_auto_clear(register, seconds)
  -- Cancel previous timer
  if clear_timer then
    clear_timer:stop()
    clear_timer:close()
    clear_timer = nil
  end

  if not seconds or seconds <= 0 then
    return
  end

  clear_timer = vim.uv.new_timer()
  clear_timer:start(
    seconds * 1000,
    0,
    vim.schedule_wrap(function()
      vim.fn.setreg(register, '')
      vim.notify('[camouflage] Clipboard cleared', vim.log.levels.INFO)
      if clear_timer then
        clear_timer:close()
        clear_timer = nil
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
      string.format('[camouflage] Copied: %s → %s', var.key, display_reg),
      vim.log.levels.INFO
    )
  end

  -- Schedule auto-clear
  if cfg.auto_clear_seconds and cfg.auto_clear_seconds > 0 then
    M.schedule_auto_clear(register, cfg.auto_clear_seconds)
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

---Cancel auto-clear timer (for testing)
function M.cancel_auto_clear()
  if clear_timer then
    clear_timer:stop()
    clear_timer:close()
    clear_timer = nil
  end
end

return M
