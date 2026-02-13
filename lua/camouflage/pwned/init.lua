---@mod camouflage.pwned Have I Been Pwned integration
---@brief [[
--- Checks masked passwords against the Have I Been Pwned database.
--- Uses k-anonymity to protect privacy (only first 5 chars of hash sent).
---
--- Usage:
---   require('camouflage.pwned').check_current()  -- Check variable under cursor
---   require('camouflage.pwned').check_line()     -- Check all on current line
---   require('camouflage.pwned').check_buffer()   -- Check all in buffer
---   require('camouflage.pwned').clear()          -- Clear marks in buffer
---@brief ]]

local M = {}

local config = require('camouflage.config')
local state = require('camouflage.state')
local parsers = require('camouflage.parsers')
local check = require('camouflage.pwned.check')
local ui = require('camouflage.pwned.ui')
local cache = require('camouflage.pwned.cache')

---Get variables for pwned checking
---If camouflage has parsed variables, use those (performance optimization)
---Otherwise, parse the file ourselves (for when camouflage is disabled)
---@param bufnr number
---@return ParsedVariable[]
local function get_variables_for_pwned(bufnr)
  -- Ensure buffer is still valid (may have been deleted in vim.schedule)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  -- First try state (camouflage is active and has parsed)
  local variables = state.get_variables(bufnr)
  if variables and #variables > 0 then
    return variables
  end

  -- Camouflage disabled or hasn't parsed yet - parse ourselves
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if not parsers.is_supported(filename) then
    return {}
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return {}
  end

  local content = table.concat(lines, '\n')
  local parsed = parsers.parse(filename, content, bufnr)
  return parsed or {}
end

---Setup pwned feature
function M.setup()
  ui.setup_highlights()
end

---Check if feature is available
---@return boolean
function M.is_available()
  return check.is_available()
end

---Get UI config from main config
---@return PwnedUIConfig
local function get_ui_config()
  local cfg = config.get()
  local pwned_cfg = cfg.pwned or {}
  return {
    show_sign = pwned_cfg.show_sign,
    show_virtual_text = pwned_cfg.show_virtual_text,
    show_line_highlight = pwned_cfg.show_line_highlight,
    sign_text = pwned_cfg.sign_text,
    virtual_text_prefix = pwned_cfg.virtual_text_prefix,
  }
end

---Find variable at cursor position
---@param bufnr number Buffer number
---@param cursor_line number 0-indexed cursor line
---@param cursor_col number 0-indexed cursor column
---@return ParsedVariable|nil
local function find_variable_at_cursor(bufnr, cursor_line, cursor_col)
  local variables = get_variables_for_pwned(bufnr)
  if #variables == 0 then
    return nil
  end

  for _, var in ipairs(variables) do
    if var.line_number == cursor_line then
      -- Check if cursor is within variable range
      if cursor_col >= var.start_index and cursor_col <= var.end_index then
        return var
      end
    end
  end

  return nil
end

---Find all variables on a line
---@param bufnr number Buffer number
---@param line number 0-indexed line number
---@return ParsedVariable[]
local function find_variables_on_line(bufnr, line)
  local variables = get_variables_for_pwned(bufnr)
  if #variables == 0 then
    return {}
  end

  local result = {}
  for _, var in ipairs(variables) do
    if var.line_number == line then
      table.insert(result, var)
    end
  end

  return result
end

---Check the variable under cursor
---@param callback fun(result: PwnedCheckResult|nil)|nil Optional callback
function M.check_current(callback)
  if not M.is_available() then
    vim.notify(
      '[camouflage] HIBP check not available (missing sha1sum/openssl or curl)',
      vim.log.levels.WARN
    )
    if callback then
      callback(nil)
    end
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1] - 1 -- Convert to 0-indexed
  local cursor_col = cursor[2]

  local var = find_variable_at_cursor(bufnr, cursor_line, cursor_col)
  if not var then
    vim.notify('[camouflage] No masked variable under cursor', vim.log.levels.INFO)
    if callback then
      callback(nil)
    end
    return
  end

  vim.notify('[camouflage] Checking "' .. var.key .. '" against HIBP...', vim.log.levels.INFO)

  check.check_variable(bufnr, var, get_ui_config(), function(result)
    if result then
      if result.pwned then
        vim.notify(
          string.format(
            '[camouflage] "%s" found in %s breaches!',
            var.key,
            ui.format_count(result.count)
          ),
          vim.log.levels.WARN
        )
      else
        vim.notify(
          '[camouflage] "' .. var.key .. '" not found in any breaches',
          vim.log.levels.INFO
        )
      end
    end
    if callback then
      callback(result)
    end
  end)
end

---Check all variables on current line
---@param callback fun(results: table<string, PwnedCheckResult>)|nil Optional callback
function M.check_line(callback)
  if not M.is_available() then
    vim.notify(
      '[camouflage] HIBP check not available (missing sha1sum/openssl or curl)',
      vim.log.levels.WARN
    )
    if callback then
      callback({})
    end
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1] - 1 -- Convert to 0-indexed

  local vars = find_variables_on_line(bufnr, cursor_line)
  if #vars == 0 then
    vim.notify('[camouflage] No masked variables on current line', vim.log.levels.INFO)
    if callback then
      callback({})
    end
    return
  end

  vim.notify(
    '[camouflage] Checking ' .. #vars .. ' variable(s) against HIBP...',
    vim.log.levels.INFO
  )

  check.check_buffer(bufnr, vars, get_ui_config(), function(results)
    local pwned_count = 0
    for _, result in pairs(results) do
      if result.pwned then
        pwned_count = pwned_count + 1
      end
    end

    if pwned_count > 0 then
      vim.notify(
        string.format('[camouflage] Found %d pwned password(s) on this line!', pwned_count),
        vim.log.levels.WARN
      )
    else
      vim.notify('[camouflage] No pwned passwords found on this line', vim.log.levels.INFO)
    end

    if callback then
      callback(results)
    end
  end)
end

---Check all variables in current buffer
---@param callback fun(results: table<string, PwnedCheckResult>)|nil Optional callback
function M.check_buffer(callback)
  if not M.is_available() then
    vim.notify(
      '[camouflage] HIBP check not available (missing sha1sum/openssl or curl)',
      vim.log.levels.WARN
    )
    if callback then
      callback({})
    end
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local variables = get_variables_for_pwned(bufnr)

  if #variables == 0 then
    vim.notify('[camouflage] No variables found in current buffer', vim.log.levels.INFO)
    if callback then
      callback({})
    end
    return
  end

  vim.notify(
    '[camouflage] Checking ' .. #variables .. ' variable(s) against HIBP...',
    vim.log.levels.INFO
  )

  check.check_buffer(bufnr, variables, get_ui_config(), function(results)
    local pwned_count = 0
    for _, result in pairs(results) do
      if result.pwned then
        pwned_count = pwned_count + 1
      end
    end

    if pwned_count > 0 then
      vim.notify(
        string.format('[camouflage] Found %d pwned password(s) in buffer!', pwned_count),
        vim.log.levels.WARN
      )
    else
      vim.notify('[camouflage] No pwned passwords found in buffer', vim.log.levels.INFO)
    end

    if callback then
      callback(results)
    end
  end)
end

---Clear all pwned marks in current buffer
function M.clear()
  ui.clear_marks(vim.api.nvim_get_current_buf())
end

---Clear all pwned marks in all buffers
function M.clear_all()
  ui.clear_all_marks()
end

---Clear cache
function M.clear_cache()
  cache.clear()
end

---Called on BufEnter when auto_check is enabled
---@param bufnr number Buffer number
function M.on_buf_enter(bufnr)
  local cfg = config.get()
  local pwned_cfg = cfg.pwned or {}

  if not pwned_cfg.auto_check then
    return
  end

  if not M.is_available() then
    return
  end

  local variables = get_variables_for_pwned(bufnr)
  if #variables == 0 then
    return
  end

  -- Check buffer silently (no notifications)
  check.check_buffer(bufnr, variables, get_ui_config(), nil)
end

---Called on BufWritePost when check_on_save is enabled
---@param bufnr number Buffer number
function M.on_buf_write(bufnr)
  local cfg = config.get()
  local pwned_cfg = cfg.pwned or {}

  if not pwned_cfg.check_on_save then
    return
  end

  if not M.is_available() then
    return
  end

  -- Clear existing marks first
  ui.clear_marks(bufnr)

  local variables = get_variables_for_pwned(bufnr)
  if #variables == 0 then
    return
  end

  -- Check buffer silently (no notifications)
  check.check_buffer(bufnr, variables, get_ui_config(), nil)
end

---Called on TextChanged when check_on_change is enabled
---Only checks variables on the current cursor line
---@param bufnr number Buffer number
function M.on_text_changed(bufnr)
  local cfg = config.get()
  local pwned_cfg = cfg.pwned or {}

  if not pwned_cfg.check_on_change then
    return
  end

  if not M.is_available() then
    return
  end

  -- Get cursor line (0-indexed)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1] - 1

  -- Clear marks on this line first (in case value changed)
  ui.clear_line_marks(bufnr, cursor_line)

  -- Get variables on current line only
  local all_variables = get_variables_for_pwned(bufnr)
  local line_variables = {}
  for _, var in ipairs(all_variables) do
    if var.line_number == cursor_line then
      table.insert(line_variables, var)
    end
  end

  if #line_variables == 0 then
    return
  end

  -- Check line variables silently (no notifications)
  check.check_buffer(bufnr, line_variables, get_ui_config(), nil)
end

return M
