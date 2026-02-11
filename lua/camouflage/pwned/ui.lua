---@mod camouflage.pwned.ui Visual indicators for pwned passwords
---@brief [[
--- Provides visual feedback for passwords found in breaches.
--- Shows signs, virtual text, and line highlights.
---@brief ]]

local M = {}

local ns_id = vim.api.nvim_create_namespace('camouflage_pwned')

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
---@field show_sign? boolean Show sign in sign column (default: true)
---@field show_virtual_text? boolean Show virtual text (default: true)
---@field show_line_highlight? boolean Highlight entire line (default: true)
---@field sign_text? string Sign text (default: "!")
---@field virtual_text_prefix? string Prefix for virtual text (default: " PWNED: ")

---Mark a line as pwned
---@param bufnr number Buffer number
---@param line number 0-indexed line number
---@param count number Number of times found in breaches
---@param config PwnedUIConfig|nil Configuration options
function M.mark_pwned(bufnr, line, count, config)
  config = config or {}
  local show_sign = config.show_sign ~= false
  local show_virtual_text = config.show_virtual_text ~= false
  local show_line_highlight = config.show_line_highlight ~= false
  local sign_text = config.sign_text or '!'
  local virtual_text_prefix = config.virtual_text_prefix or ' PWNED: '

  -- Validate buffer and line
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line < 0 or line >= line_count then
    return
  end

  ---@type vim.api.keyset.set_extmark
  local extmark_opts = {
    id = line + 1, -- Use line+1 as ID to allow one mark per line
    priority = 200, -- Higher than normal extmarks
  }

  -- Line highlight
  if show_line_highlight then
    extmark_opts.line_hl_group = 'CamouflagePwned'
  end

  -- Sign
  if show_sign then
    extmark_opts.sign_text = sign_text
    extmark_opts.sign_hl_group = 'CamouflagePwnedSign'
  end

  -- Virtual text
  if show_virtual_text then
    local formatted = M.format_count(count)
    extmark_opts.virt_text = {
      { virtual_text_prefix .. formatted .. ' exposures', 'CamouflagePwnedVirtualText' },
    }
    extmark_opts.virt_text_pos = 'eol'
  end

  vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, extmark_opts)
end

---Clear all pwned marks from a buffer
---@param bufnr number Buffer number
function M.clear_marks(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  end
end

---Clear all pwned marks from all buffers
function M.clear_all_marks()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    end
  end
end

---Get namespace id
---@return number
function M.get_namespace()
  return ns_id
end

return M
