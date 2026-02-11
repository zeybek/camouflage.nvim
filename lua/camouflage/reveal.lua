---@mod camouflage.reveal Reveal masked values temporarily

local M = {}

local state = require('camouflage.state')
local config = require('camouflage.config')
local core = require('camouflage.core')
local hooks = require('camouflage.hooks')

-- Reveal state
local revealed_state = {
  bufnr = nil,
  line = nil, -- 1-indexed
  autocmd_id = nil,
  hook_id = nil, -- variable_detected hook to skip revealed line
}

-- Follow cursor state (global)
local follow_state = {
  enabled = false,
  autocmd_id = nil,
}

---Get reveal configuration with defaults
---@return table
local function get_reveal_config()
  local cfg = config.get()
  return vim.tbl_deep_extend('force', {
    highlight_group = 'CamouflageRevealed',
    notify = false,
  }, cfg.reveal or {})
end

---Get the line number for a variable
---@param bufnr number
---@param var table
---@return number|nil 1-indexed line number
local function get_var_line(bufnr, var)
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return nil
  end
  local line_offsets = core.compute_line_offsets(lines)
  local pos = core.index_to_position(bufnr, var.start_index, lines, line_offsets)
  return pos and (pos.row + 1) or nil
end

---Check if a line has any masked variables
---@param bufnr number
---@param line number 1-indexed line number
---@return boolean
local function line_has_variables(bufnr, line)
  local variables = state.get_variables(bufnr)
  for _, var in ipairs(variables) do
    local var_line = get_var_line(bufnr, var)
    if var_line == line then
      return true
    end
  end
  return false
end

---Clear extmarks for a specific line
---@param bufnr number Buffer number
---@param line number 0-indexed line number
---@return nil
local function clear_line_extmarks(bufnr, line)
  -- nvim_buf_clear_namespace: line_end is EXCLUSIVE
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.namespace, line, line + 1)
end

---Apply revealed highlight to values on a line
---@param bufnr number Buffer number
---@param line number 0-indexed line number
---@return nil
local function apply_revealed_highlight(bufnr, line)
  local cfg = get_reveal_config()
  local variables = state.get_variables(bufnr)
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return
  end
  local line_offsets = core.compute_line_offsets(lines)

  for _, var in ipairs(variables) do
    local var_pos = core.index_to_position(bufnr, var.start_index, lines, line_offsets)
    if var_pos and var_pos.row == line then
      local end_pos = core.index_to_position(bufnr, var.end_index, lines, line_offsets)
      if end_pos then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, state.namespace, line, var_pos.col, {
          end_row = end_pos.row,
          end_col = end_pos.col,
          hl_group = cfg.highlight_group,
          priority = 101,
        })
      end
    end
  end
end

---Setup hook to prevent re-masking revealed line
---@return nil
local function setup_reveal_hook()
  revealed_state.hook_id = hooks.on('variable_detected', function(bufnr, var)
    if revealed_state.bufnr == bufnr then
      local var_line = get_var_line(bufnr, var)
      if var_line == revealed_state.line then
        return false -- Skip masking this variable
      end
    end
  end)
end

---Cleanup reveal hook
---@return nil
local function cleanup_reveal_hook()
  if revealed_state.hook_id then
    hooks.off('variable_detected', revealed_state.hook_id)
    revealed_state.hook_id = nil
  end
end

---Setup autocmd for auto-hide
---@param bufnr number Buffer number
---@param revealed_line number 1-indexed line number
---@return nil
local function setup_auto_hide(bufnr, revealed_line)
  -- Skip auto-hide setup in follow cursor mode (follow mode handles its own cursor tracking)
  if follow_state.enabled then
    return
  end

  if revealed_state.autocmd_id then
    pcall(vim.api.nvim_del_autocmd, revealed_state.autocmd_id)
  end

  revealed_state.autocmd_id = vim.api.nvim_create_autocmd(
    { 'CursorMoved', 'CursorMovedI', 'BufLeave', 'WinLeave' },
    {
      buffer = bufnr,
      callback = function(args)
        if args.event == 'BufLeave' or args.event == 'WinLeave' then
          M.hide()
          return true
        end

        local cursor = vim.api.nvim_win_get_cursor(0)
        if cursor[1] ~= revealed_line then
          M.hide()
          return true
        end
      end,
      group = state.augroup,
    }
  )
end

---Reveal the current line
---@return nil
function M.reveal_line()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] -- 1-indexed
  local line_0 = line - 1 -- 0-indexed

  -- Check if buffer has any variables
  local variables = state.get_variables(bufnr)
  if #variables == 0 then
    vim.notify('[camouflage] No masked variables in buffer', vim.log.levels.WARN)
    return
  end

  -- Already revealed on this line?
  if revealed_state.bufnr == bufnr and revealed_state.line == line then
    return
  end

  -- Hide previous
  if revealed_state.bufnr then
    M.hide()
  end

  -- HOOK: before_reveal
  local should_continue = hooks.emit('before_reveal', bufnr, line)
  if should_continue == false then
    return
  end

  -- Store state
  revealed_state.bufnr = bufnr
  revealed_state.line = line

  -- Setup hook to prevent re-masking
  setup_reveal_hook()

  -- Clear extmarks on this line
  clear_line_extmarks(bufnr, line_0)

  -- Apply highlight
  apply_revealed_highlight(bufnr, line_0)

  -- Setup auto-hide
  setup_auto_hide(bufnr, line)

  -- Notify
  local cfg = get_reveal_config()
  if cfg.notify then
    vim.notify('[camouflage] Line revealed', vim.log.levels.INFO)
  end

  -- HOOK: after_reveal
  hooks.emit('after_reveal', bufnr, line)
end

---Hide revealed line
---@return nil
function M.hide()
  if not revealed_state.bufnr then
    return
  end

  -- Cleanup autocmd
  if revealed_state.autocmd_id then
    pcall(vim.api.nvim_del_autocmd, revealed_state.autocmd_id)
    revealed_state.autocmd_id = nil
  end

  -- Cleanup hook
  cleanup_reveal_hook()

  -- Clear state BEFORE re-applying (important for hook to work correctly)
  local was_bufnr = revealed_state.bufnr
  revealed_state.bufnr = nil
  revealed_state.line = nil

  -- Re-apply decorations
  if vim.api.nvim_buf_is_valid(was_bufnr) then
    core.apply_decorations(was_bufnr)
  end

  -- Notify
  local cfg = get_reveal_config()
  if cfg.notify then
    vim.notify('[camouflage] Line masked', vim.log.levels.INFO)
  end
end

---Toggle reveal on current line
---@return nil
function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)

  if revealed_state.bufnr == bufnr and revealed_state.line == cursor[1] then
    M.hide()
  else
    M.reveal_line()
  end
end

---Check if currently revealing
---@return boolean
function M.is_revealed()
  return revealed_state.bufnr ~= nil
end

---Get revealed line info
---@return { bufnr: number, line: number }|nil
function M.get_revealed()
  if revealed_state.bufnr then
    return { bufnr = revealed_state.bufnr, line = revealed_state.line }
  end
  return nil
end

-- ============================================================================
-- Follow Cursor Mode
-- ============================================================================

---Check if follow cursor mode is enabled
---@return boolean
function M.is_follow_cursor_enabled()
  return follow_state.enabled
end

---Internal: Reveal a specific line without notifications (for follow mode)
---@param bufnr number Buffer number
---@param line number 1-indexed line number
---@return nil
local function reveal_line_silent(bufnr, line)
  local line_0 = line - 1

  -- Store state
  revealed_state.bufnr = bufnr
  revealed_state.line = line

  -- Setup hook to prevent re-masking
  setup_reveal_hook()

  -- Clear extmarks on this line
  clear_line_extmarks(bufnr, line_0)

  -- Apply highlight
  apply_revealed_highlight(bufnr, line_0)
end

---Internal: Hide current reveal without notifications (for follow mode)
---@return nil
local function hide_silent()
  if not revealed_state.bufnr then
    return
  end

  -- Cleanup autocmd (if any)
  if revealed_state.autocmd_id then
    pcall(vim.api.nvim_del_autocmd, revealed_state.autocmd_id)
    revealed_state.autocmd_id = nil
  end

  -- Cleanup hook
  cleanup_reveal_hook()

  -- Clear state BEFORE re-applying
  local was_bufnr = revealed_state.bufnr
  revealed_state.bufnr = nil
  revealed_state.line = nil

  -- Re-apply decorations
  if vim.api.nvim_buf_is_valid(was_bufnr) then
    core.apply_decorations(was_bufnr)
  end
end

---Internal: Handle cursor movement in follow mode
---@param bufnr number Buffer number
---@return nil
local function on_follow_cursor_moved(bufnr)
  -- Only work on camouflage-enabled buffers
  if not state.is_buffer_masked(bufnr) then
    -- If we're in a non-masked buffer, hide any active reveal
    if revealed_state.bufnr then
      hide_silent()
    end
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] -- 1-indexed

  -- Same line, same buffer? Skip
  if revealed_state.bufnr == bufnr and revealed_state.line == line then
    return
  end

  -- Check if this line has any masked variables
  local has_vars = line_has_variables(bufnr, line)

  -- Hide previous reveal
  if revealed_state.bufnr then
    hide_silent()
  end

  -- Reveal new line if it has variables
  if has_vars then
    reveal_line_silent(bufnr, line)
  end
end

---Start follow cursor mode
---@return nil
function M.start_follow_cursor()
  if follow_state.enabled then
    return
  end

  -- HOOK: before_follow_start
  local should_continue = hooks.emit('before_follow_start')
  if should_continue == false then
    return
  end

  follow_state.enabled = true

  -- Create global autocmd for cursor movement
  follow_state.autocmd_id = vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = state.augroup,
    callback = function(args)
      on_follow_cursor_moved(args.buf)
    end,
    desc = 'Camouflage follow cursor mode',
  })

  -- Reveal current line immediately (if applicable)
  local bufnr = vim.api.nvim_get_current_buf()
  on_follow_cursor_moved(bufnr)

  -- Notify
  local cfg = get_reveal_config()
  if cfg.notify then
    vim.notify('[camouflage] Follow cursor mode enabled', vim.log.levels.INFO)
  end

  -- HOOK: after_follow_start
  hooks.emit('after_follow_start')
end

---Stop follow cursor mode
---@return nil
function M.stop_follow_cursor()
  if not follow_state.enabled then
    return
  end

  -- HOOK: before_follow_stop
  local should_continue = hooks.emit('before_follow_stop')
  if should_continue == false then
    return
  end

  -- Hide any active reveal
  if revealed_state.bufnr then
    hide_silent()
  end

  -- Delete autocmd
  if follow_state.autocmd_id then
    pcall(vim.api.nvim_del_autocmd, follow_state.autocmd_id)
    follow_state.autocmd_id = nil
  end

  follow_state.enabled = false

  -- Notify
  local cfg = get_reveal_config()
  if cfg.notify then
    vim.notify('[camouflage] Follow cursor mode disabled', vim.log.levels.INFO)
  end

  -- HOOK: after_follow_stop
  hooks.emit('after_follow_stop')
end

---Toggle follow cursor mode
---@param opts? { force_disable: boolean }
function M.toggle_follow_cursor(opts)
  opts = opts or {}

  if opts.force_disable then
    M.stop_follow_cursor()
  elseif follow_state.enabled then
    M.stop_follow_cursor()
  else
    M.start_follow_cursor()
  end
end

return M
