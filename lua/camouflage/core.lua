---@mod camouflage.core Core decoration engine

local M = {}

local state = require('camouflage.state')
local config = require('camouflage.config')
local styles = require('camouflage.styles')
local parsers = require('camouflage.parsers')
local hooks = require('camouflage.hooks')
local log = require('camouflage.log')
local position = require('camouflage.position')
local policy = require('camouflage.policy')
local check_registry = require('camouflage.checks.registry')

-- Position math lives in the leaf module camouflage.position so yank/pwned can
-- reuse it without depending on the whole decoration engine. These permanent
-- aliases keep core.compute_line_offsets / core.index_to_position working for
-- existing callers (reveal, yank, tests).
M.compute_line_offsets = position.compute_line_offsets
M.index_to_position = position.index_to_position

---Get the highlight group to use for masking
---@param cfg table Configuration
---@return string highlight group name
local function get_highlight_group(cfg)
  -- Use custom CamouflageMask if colors are configured
  if cfg.colors then
    return 'CamouflageMask'
  end
  return cfg.highlight_group
end

---Disable 'wrap' on every window showing the buffer (extmark overlays glitch
---with wrap on), saving each window's original value so it can be restored.
---Only touches windows whose wrap is currently on, and saves the marker once,
---so it never clobbers a user's deliberate `:set nowrap`.
---@param bufnr number
local function disable_wrap(bufnr)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_get_option_value('wrap', { win = win }) then
      if not pcall(vim.api.nvim_win_get_var, win, 'camouflage_saved_wrap') then
        vim.api.nvim_win_set_var(win, 'camouflage_saved_wrap', true)
      end
      vim.api.nvim_set_option_value('wrap', false, { win = win })
    end
  end
end

---Restore 'wrap' on windows where camouflage previously turned it off.
---@param bufnr number
local function restore_wrap(bufnr)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    local ok, saved = pcall(vim.api.nvim_win_get_var, win, 'camouflage_saved_wrap')
    if ok and saved then
      vim.api.nvim_set_option_value('wrap', true, { win = win })
      pcall(vim.api.nvim_win_del_var, win, 'camouflage_saved_wrap')
    end
  end
end

---Reset state after clearing decorations on a no-mask path: drop stale
---variables (so yank/reveal/pwned can't act on now-unmasked data) and restore
---window wrap.
---@param bufnr number
local function reset_mask_state(bufnr)
  state.update_buffer(bufnr, {
    enabled = false,
    variables = {},
  })
  state.clear_policy_stats(bufnr)
  restore_wrap(bufnr)
end

---@param bufnr number
---@param parser_name string|nil
---@param policy_stats table|nil
local function reset_mask_state_with_policy(bufnr, parser_name, policy_stats)
  state.update_buffer(bufnr, {
    enabled = false,
    variables = {},
    parser = parser_name,
    policy_stats = policy_stats,
  })
  restore_wrap(bufnr)
end

M.restore_wrap = restore_wrap

---Apply decorations to mask sensitive values in a buffer
---@param bufnr number Buffer number
---@param override_filename string|nil Optional filename for buffers without names (e.g., snacks preview)
function M.apply_decorations(bufnr, override_filename)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Always clear first so a no-mask outcome (disabled, too large, no parser, no
  -- variables) never leaves stale extmarks drifting over the buffer.
  M.clear_decorations(bufnr)
  local check_run_id = check_registry.begin_decorate(bufnr)

  -- Buffer-local config (vim.b.camouflage_*) overrides the global config; with
  -- no overrides this returns the shared config table at no extra cost.
  local cfg = config.get_for_buffer(bufnr)
  if not cfg.enabled then
    reset_mask_state(bufnr)
    return
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if cfg.max_lines and line_count > cfg.max_lines then
    reset_mask_state(bufnr)
    return
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    log.pcall_error('nvim_buf_get_lines', lines, { bufnr = bufnr })
    reset_mask_state(bufnr)
    return
  end
  local content = table.concat(lines, '\n')

  local filename = override_filename or vim.api.nvim_buf_get_name(bufnr)
  if filename == '' then
    reset_mask_state(bufnr)
    return
  end

  -- Find parser once and pass it to parse() to avoid redundant lookup
  local parser, parser_name = parsers.find_parser_for_file(filename)
  if not parser then
    reset_mask_state(bufnr)
    return
  end

  -- HOOK: before_decorate
  local should_continue = hooks.emit('before_decorate', bufnr, filename)
  if should_continue == false then
    reset_mask_state(bufnr)
    return
  end

  local variables = parsers.parse(filename, content, bufnr, parser, parser_name)
  if #variables == 0 then
    reset_mask_state(bufnr)
    return
  end

  local policy_variables, policy_result = policy.filter_variables({
    bufnr = bufnr,
    filename = filename,
    parser_name = parser_name,
    variables = variables,
    config = cfg,
  })
  if #policy_variables == 0 then
    reset_mask_state_with_policy(bufnr, parser_name, policy_result.stats)
    return
  end

  -- HOOK: variable_detected (filter variables)
  local filtered_variables = {}
  for _, var in ipairs(policy_variables) do
    local should_mask = hooks.emit('variable_detected', bufnr, var)
    if should_mask ~= false then
      table.insert(filtered_variables, var)
    end
  end

  if #filtered_variables == 0 then
    reset_mask_state(bufnr)
    return
  end

  state.update_buffer(bufnr, {
    enabled = true,
    variables = filtered_variables,
    parser = parser_name,
    policy_stats = policy_result.stats,
  })
  state.clear_dirty(bufnr)

  check_registry.run({
    bufnr = bufnr,
    filename = filename,
    parser_name = parser_name,
    variables = filtered_variables,
    config = cfg,
    run_id = check_run_id,
  })

  -- Pre-compute line offsets for O(1) index lookups
  local line_offsets = M.compute_line_offsets(lines)

  for _, var in ipairs(filtered_variables) do
    M.apply_single_decoration(bufnr, var, cfg, lines, line_offsets)
  end

  disable_wrap(bufnr)

  -- HOOK: after_decorate
  hooks.emit('after_decorate', bufnr, filtered_variables)
end

---@param bufnr number
---@param var table
---@param cfg table
---@param lines string[]
---@param line_offsets number[]|nil Pre-computed cumulative line offsets for O(1) lookup
function M.apply_single_decoration(bufnr, var, cfg, lines, line_offsets)
  if not var.value or var.value:match('^%s*$') then
    return
  end

  local start_pos = M.index_to_position(bufnr, var.start_index, lines, line_offsets)
  local end_pos = M.index_to_position(bufnr, var.end_index, lines, line_offsets)

  if not start_pos or not end_pos then
    return
  end

  local hl_group = get_highlight_group(cfg)

  -- Handle multiline values: apply extmark per line
  if var.is_multiline and start_pos.row ~= end_pos.row then
    M.apply_multiline_decoration(bufnr, var, cfg, lines, start_pos, end_pos, hl_group)
  else
    -- Single line value (mask sized by display cells, not bytes)
    local masked_text =
      styles.generate_hidden_text(cfg.style, vim.fn.strdisplaywidth(var.value), var.value)
    local ok, err =
      pcall(vim.api.nvim_buf_set_extmark, bufnr, state.namespace, start_pos.row, start_pos.col, {
        end_row = end_pos.row,
        end_col = end_pos.col,
        virt_text = { { masked_text, hl_group } },
        virt_text_pos = 'overlay',
        hl_mode = 'combine',
        priority = 100,
      })
    if not ok then
      log.pcall_error(
        'nvim_buf_set_extmark',
        err,
        { bufnr = bufnr, row = start_pos.row, col = start_pos.col }
      )
    end
  end
end

---Apply decorations for multiline values (one extmark per line)
---@param bufnr number
---@param var table
---@param cfg table
---@param lines string[]
---@param start_pos {row: number, col: number}
---@param end_pos {row: number, col: number}
---@param hl_group string Highlight group to use
function M.apply_multiline_decoration(bufnr, var, cfg, lines, start_pos, end_pos, hl_group)
  for row = start_pos.row, end_pos.row do
    local line = lines[row + 1] -- lines is 1-indexed
    if not line then
      break
    end

    local col_start, col_end
    if row == start_pos.row then
      -- First line: from start_pos.col to end of line
      col_start = start_pos.col
      col_end = #line
    elseif row == end_pos.row then
      -- Last line: from start of content to end_pos.col
      col_start = line:match('^(%s*)'):len() -- Start after indentation
      col_end = end_pos.col
    else
      -- Middle lines: mask from indentation to end of line
      col_start = line:match('^(%s*)'):len()
      col_end = #line
    end

    -- Skip empty lines or lines with only whitespace
    local line_content = line:sub(col_start + 1, col_end)
    if line_content:match('^%s*$') then
      goto continue
    end

    local masked_text =
      styles.generate_hidden_text(cfg.style, vim.fn.strdisplaywidth(line_content), line_content)
    local ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, state.namespace, row, col_start, {
      end_row = row,
      end_col = col_end,
      virt_text = { { masked_text, hl_group } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
      priority = 100,
    })
    if not ok then
      log.pcall_error('nvim_buf_set_extmark', err, { bufnr = bufnr, row = row, col = col_start })
    end

    ::continue::
  end
end

---@param bufnr number|nil
function M.clear_decorations(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ok, err = pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.namespace, 0, -1)
  if not ok then
    log.pcall_error('nvim_buf_clear_namespace', err, { bufnr = bufnr })
  end
end

---Refresh decorations for current buffer
---@return nil
function M.refresh()
  M.apply_decorations(vim.api.nvim_get_current_buf())
end

---Refresh decorations everywhere a config change must take effect.
---Visible supported buffers are re-decorated now (deduped so a buffer shown in
---two windows parses once); masked-but-hidden buffers are only marked dirty and
---re-decorate when next displayed (see the BufWinEnter handler) — re-parsing
---every loaded buffer on each config change would be needlessly expensive.
---Also sweeps state for buffers that are no longer valid.
---@return nil
function M.refresh_all()
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not seen[bufnr] then
      seen[bufnr] = true
      local filename = vim.api.nvim_buf_get_name(bufnr)
      -- apply_decorations handles parser lookup internally, but is_supported
      -- avoids processing unrelated buffers.
      if parsers.is_supported(filename) then
        M.apply_decorations(bufnr)
      end
    end
  end

  for bufnr in pairs(state.buffers) do
    if not vim.api.nvim_buf_is_valid(bufnr) then
      state.remove_buffer(bufnr) -- backstop for buffers that never fired BufWipeout
    elseif not seen[bufnr] and state.is_buffer_masked(bufnr) then
      state.mark_dirty(bufnr)
    end
  end
end

---@return boolean
function M.is_masked()
  return state.is_buffer_masked(vim.api.nvim_get_current_buf())
end

return M
