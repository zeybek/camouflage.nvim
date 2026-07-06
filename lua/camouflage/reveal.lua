---@mod camouflage.reveal Reveal masked values temporarily

local M = {}

local state = require('camouflage.state')
local config = require('camouflage.config')
local core = require('camouflage.core')
local hooks = require('camouflage.hooks')
local log = require('camouflage.log')

-- Separate namespace for the reveal anchor extmark: state.namespace is cleared
-- wholesale on every re-decoration, so the anchor must live elsewhere to keep
-- tracking the revealed line as text above it is inserted/deleted.
local anchor_ns = vim.api.nvim_create_namespace('camouflage_reveal_anchor')

-- Reveal state
local revealed_state = {
  bufnr = nil,
  line = nil, -- 1-indexed (fallback; the anchor extmark is authoritative)
  anchor_id = nil, -- extmark id tracking the revealed line through edits
  autocmd_id = nil,
  hook_id = nil, -- variable_detected hook to skip revealed line
  after_decorate_hook_id = nil, -- after_decorate hook to restore revealed multiline rows
}

---Resolve the currently revealed line (1-indexed) from the anchor extmark,
---falling back to the stored integer if the anchor is gone.
---@return number|nil
local function current_revealed_line()
  if
    revealed_state.bufnr
    and revealed_state.anchor_id
    and vim.api.nvim_buf_is_valid(revealed_state.bufnr)
  then
    local mark = vim.api.nvim_buf_get_extmark_by_id(
      revealed_state.bufnr,
      anchor_ns,
      revealed_state.anchor_id,
      {}
    )
    if mark and mark[1] then
      return mark[1] + 1
    end
  end
  return revealed_state.line
end

---Set the reveal anchor extmark on a 0-indexed line.
---@param bufnr number
---@param line_0 number
local function set_anchor(bufnr, line_0)
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, anchor_ns, line_0, 0, {})
  revealed_state.anchor_id = ok and id or nil
end

---Remove the reveal anchor extmark.
---@param bufnr number|nil
local function clear_anchor(bufnr)
  if bufnr and revealed_state.anchor_id and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, anchor_ns, revealed_state.anchor_id)
  end
  revealed_state.anchor_id = nil
end

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

---Get the visible value range for a variable on a specific line.
---@param var table
---@param line_0 number 0-indexed line number
---@param lines string[]
---@param line_offsets number[]
---@return number|nil col_start
---@return number|nil col_end
local function var_range_on_line(var, line_0, lines, line_offsets)
  local line = lines[line_0 + 1]
  local line_start = line_offsets[line_0 + 1]
  if not line or not line_start or not var.start_index then
    return nil, nil
  end

  local value_end = var.end_index or var.start_index
  if value_end <= var.start_index then
    value_end = var.start_index + #(var.value or '')
  end

  local line_end = line_start + #line
  local start_index = math.max(var.start_index, line_start)
  local end_index = math.min(value_end, line_end)
  if end_index <= start_index then
    return nil, nil
  end

  local col_start = start_index - line_start
  local col_end = end_index - line_start
  local line_content = line:sub(col_start + 1, col_end)
  if line_content:match('^%s*$') then
    return nil, nil
  end

  return col_start, col_end
end

---@param bufnr number
---@param var table
---@param line_0 number 0-indexed line number
---@return boolean
local function var_has_value_on_line(bufnr, var, line_0)
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return false
  end

  local line_offsets = core.compute_line_offsets(lines)
  local col_start = var_range_on_line(var, line_0, lines, line_offsets)
  return col_start ~= nil
end

---Check if a line has any masked variables
---@param bufnr number
---@param line number 1-indexed line number
---@return boolean
local function line_has_variables(bufnr, line)
  local variables = state.get_variables(bufnr)
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return false
  end

  local line_0 = line - 1
  local line_offsets = core.compute_line_offsets(lines)
  for _, var in ipairs(variables) do
    if var_range_on_line(var, line_0, lines, line_offsets) then
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
  local ok, err = pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.namespace, line, line + 1)
  if not ok then
    log.pcall_error('nvim_buf_clear_namespace', err, { bufnr = bufnr, line = line })
  end
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
    local col_start, col_end = var_range_on_line(var, line, lines, line_offsets)
    if col_start and col_end then
      local extmark_ok, extmark_err =
        pcall(vim.api.nvim_buf_set_extmark, bufnr, state.namespace, line, col_start, {
          end_row = line,
          end_col = col_end,
          hl_group = cfg.highlight_group,
          priority = 101,
        })
      if not extmark_ok then
        log.pcall_error(
          'nvim_buf_set_extmark',
          extmark_err,
          { bufnr = bufnr, line = line, col = col_start }
        )
      end
    end
  end
end

---Setup hook to prevent re-masking revealed line
---@return nil
local function setup_reveal_hook()
  revealed_state.hook_id = hooks.on('variable_detected', function(bufnr, var)
    if revealed_state.bufnr == bufnr then
      local line = current_revealed_line()
      if line and not var.is_multiline and var_has_value_on_line(bufnr, var, line - 1) then
        return false -- Skip masking this variable
      end
    end
  end)

  revealed_state.after_decorate_hook_id = hooks.on('after_decorate', function(bufnr)
    if revealed_state.bufnr ~= bufnr then
      return
    end

    local line = current_revealed_line()
    if line then
      clear_line_extmarks(bufnr, line - 1)
      apply_revealed_highlight(bufnr, line - 1)
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
  if revealed_state.after_decorate_hook_id then
    hooks.off('after_decorate', revealed_state.after_decorate_hook_id)
    revealed_state.after_decorate_hook_id = nil
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
    local ok, err = pcall(vim.api.nvim_del_autocmd, revealed_state.autocmd_id)
    if not ok then
      log.pcall_error('nvim_del_autocmd', err, { autocmd_id = revealed_state.autocmd_id })
    end
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
        -- Compare against the anchor's current line so edits above the revealed
        -- line don't spuriously trigger auto-hide.
        if cursor[1] ~= current_revealed_line() then
          M.hide()
          return true
        end
      end,
      group = state.runtime_augroup,
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
  if revealed_state.bufnr == bufnr and current_revealed_line() == line then
    return
  end

  -- Only reveal lines that actually contain masked values. Checked before
  -- hiding any existing reveal, so a no-op reveal leaves the current one intact.
  if not line_has_variables(bufnr, line) then
    vim.notify('[camouflage] No masked values on this line', vim.log.levels.WARN)
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
  set_anchor(bufnr, line_0)

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
    local ok, err = pcall(vim.api.nvim_del_autocmd, revealed_state.autocmd_id)
    if not ok then
      log.pcall_error('nvim_del_autocmd', err, { autocmd_id = revealed_state.autocmd_id })
    end
    revealed_state.autocmd_id = nil
  end

  -- Cleanup hook
  cleanup_reveal_hook()

  -- Clear state BEFORE re-applying (important for hook to work correctly)
  local was_bufnr = revealed_state.bufnr
  clear_anchor(was_bufnr)
  revealed_state.bufnr = nil
  revealed_state.line = nil

  -- Re-apply decorations
  if was_bufnr and vim.api.nvim_buf_is_valid(was_bufnr) then
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

  if revealed_state.bufnr == bufnr and current_revealed_line() == cursor[1] then
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
    return { bufnr = revealed_state.bufnr, line = current_revealed_line() }
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
  set_anchor(bufnr, line_0)

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
    local ok, err = pcall(vim.api.nvim_del_autocmd, revealed_state.autocmd_id)
    if not ok then
      log.pcall_error('nvim_del_autocmd', err, { autocmd_id = revealed_state.autocmd_id })
    end
    revealed_state.autocmd_id = nil
  end

  -- Cleanup hook
  cleanup_reveal_hook()

  -- Clear state BEFORE re-applying
  local was_bufnr = revealed_state.bufnr
  clear_anchor(was_bufnr)
  revealed_state.bufnr = nil
  revealed_state.line = nil

  -- Re-apply decorations
  if was_bufnr and vim.api.nvim_buf_is_valid(was_bufnr) then
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
  if revealed_state.bufnr == bufnr and current_revealed_line() == line then
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
    group = state.runtime_augroup,
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
    local ok, err = pcall(vim.api.nvim_del_autocmd, follow_state.autocmd_id)
    if not ok then
      log.pcall_error('nvim_del_autocmd', err, { autocmd_id = follow_state.autocmd_id })
    end
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
