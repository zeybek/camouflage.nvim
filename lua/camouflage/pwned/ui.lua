---@mod camouflage.pwned.ui Visual indicators for pwned passwords
---@brief [[
--- Provides visual feedback for passwords found in breaches via the
--- centralized camouflage.checks badges renderer. Public API
--- (mark_pwned, clear_marks, clear_line_marks, get_namespace, ...) is
--- preserved for backward compatibility with existing callers and tests.
---@brief ]]

local M = {}

local checks = require('camouflage.checks')

local CHECK_NAME = 'pwned'

---Setup highlight groups
function M.setup_highlights()
  -- Line background (reddish)
  vim.api.nvim_set_hl(0, 'CamouflagePwned', {
    bg = '#3d1f1f',
    default = true,
  })

  -- Sign column
  vim.api.nvim_set_hl(0, 'CamouflagePwnedSign', {
    fg = '#ff6b6b',
    bold = true,
    default = true,
  })

  -- Virtual text
  vim.api.nvim_set_hl(0, 'CamouflagePwnedVirtualText', {
    fg = '#ff6b6b',
    italic = true,
    default = true,
  })
end

---Format count for display (e.g., 9545824 -> "9.5M", 152000 -> "152K")
---@param count number
---@return string
function M.format_count(count)
  if count >= 1000000 then
    return string.format('%.1fM', count / 1000000)
  elseif count >= 1000 then
    return string.format('%.0fK', count / 1000)
  else
    return tostring(count)
  end
end

---@class PwnedUIConfig
---@field show_sign? boolean
---@field show_virtual_text? boolean
---@field show_line_highlight? boolean
---@field sign_text? string
---@field sign_hl? string
---@field virtual_text_format? string
---@field virtual_text_hl? string
---@field virtual_text_prefix? string Deprecated fallback
---@field line_hl? string

---Mark a line as pwned
---@param bufnr integer
---@param line integer 0-indexed
---@param count number Number of times found in breaches
---@param config PwnedUIConfig|nil
function M.mark_pwned(bufnr, line, count, config)
  config = config or {}
  local show_sign = config.show_sign ~= false
  local show_virtual_text = config.show_virtual_text ~= false
  local show_line_highlight = config.show_line_highlight ~= false
  local virtual_text_format = config.virtual_text_format

  if not virtual_text_format then
    local virtual_text_prefix = config.virtual_text_prefix or ' PWNED: '
    virtual_text_format = virtual_text_prefix .. '%s exposures'
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line < 0 or line >= line_count then
    return
  end

  local formatted = M.format_count(count)

  ---@type CheckResult
  local result = {
    severity = 'error',
    text = show_virtual_text and string.format(virtual_text_format, formatted) or '',
    hl_group = config.virtual_text_hl or 'CamouflagePwnedVirtualText',
    sign_text = show_sign and (config.sign_text or '!') or nil,
    sign_hl = config.sign_hl or 'CamouflagePwnedSign',
    line_hl = show_line_highlight and (config.line_hl or 'CamouflagePwned') or nil,
    priority = 100,
    data = { count = count },
  }

  checks.set_result(bufnr, line, CHECK_NAME, result)
end

---Clear all pwned marks from a buffer
---@param bufnr integer
function M.clear_marks(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    checks.clear_check(bufnr, CHECK_NAME)
  end
end

---Clear pwned marks from a specific line
---@param bufnr integer
---@param line integer 0-indexed
function M.clear_line_marks(bufnr, line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  checks.set_result(bufnr, line, CHECK_NAME, nil)
end

---Clear all pwned marks from all buffers
function M.clear_all_marks()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      checks.clear_check(bufnr, CHECK_NAME)
    end
  end
end

---Get namespace id (badges namespace — single shared namespace for all checks).
---@return integer
function M.get_namespace()
  return checks.badges.get_namespace()
end

return M
