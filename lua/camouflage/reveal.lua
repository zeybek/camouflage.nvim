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

---Clear extmarks for a specific line
---@param bufnr number
---@param line number 0-indexed
local function clear_line_extmarks(bufnr, line)
  -- nvim_buf_clear_namespace: line_end is EXCLUSIVE
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.namespace, line, line + 1)
end

---Apply revealed highlight to values on a line
---@param bufnr number
---@param line number 0-indexed
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
local function cleanup_reveal_hook()
  if revealed_state.hook_id then
    hooks.off('variable_detected', revealed_state.hook_id)
    revealed_state.hook_id = nil
  end
end

---Setup autocmd for auto-hide
---@param bufnr number
---@param revealed_line number 1-indexed
local function setup_auto_hide(bufnr, revealed_line)
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

return M
