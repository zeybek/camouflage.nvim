---@mod camouflage.integrations.preview Mask more picker previews

-- Telescope and Snacks previews are masked from `camouflage.init`. This adds
-- the other two pickers people use, and blink.cmp, which had no equivalent of
-- the nvim-cmp handling.
--
-- A preview buffer holds another file's text under a name of its own, so the
-- decoration pass is given the real filename to pick a parser with.

local M = {}

local config = require('camouflage.config')
local parsers = require('camouflage.parsers')

---Mask a preview buffer as if it were the file it shows.
---@param bufnr number|nil
---@param filename string|nil
---@return boolean masked
function M.mask_buffer(bufnr, filename)
  if type(bufnr) ~= 'number' or type(filename) ~= 'string' or filename == '' then
    return false
  end
  if not config.is_enabled() or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if not parsers.is_supported(filename) then
    return false
  end

  require('camouflage.state').init_buffer(bufnr)
  require('camouflage.core').apply_decorations(bufnr, filename)
  return true
end

---@type table<string, boolean>
local wrapped = {}

---fzf-lua draws file previews through one method, whatever the picker was.
---@return nil
local function setup_fzf()
  if wrapped.fzf then
    return
  end
  local ok, builtin = pcall(require, 'fzf-lua.previewer.builtin')
  if not ok or type(builtin.buffer_or_file) ~= 'table' then
    return
  end
  local original = builtin.buffer_or_file.preview_buf_post
  if type(original) ~= 'function' then
    return
  end

  builtin.buffer_or_file.preview_buf_post = function(self, entry, ...)
    local result = original(self, entry, ...)
    local path = entry and (entry.path or entry.bufname or entry.uri)
    M.mask_buffer(self and self.preview_bufnr, path)
    return result
  end
  wrapped.fzf = true
end

---mini.pick renders every preview through one function.
---@return nil
local function setup_mini_pick()
  if wrapped.mini_pick then
    return
  end
  local ok, pick = pcall(require, 'mini.pick')
  if not ok or type(pick.default_preview) ~= 'function' then
    return
  end

  local original = pick.default_preview
  pick.default_preview = function(buf_id, item, opts)
    local result = original(buf_id, item, opts)
    local path = type(item) == 'table' and (item.path or item.text) or item
    M.mask_buffer(buf_id, type(path) == 'string' and path or nil)
    return result
  end
  wrapped.mini_pick = true
end

---blink.cmp reads `vim.b.completion` before it runs, so a masked buffer can
---turn it off the same way nvim-cmp is turned off.
---@param bufnr number
local function sync_blink(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local cfg = config.get()
  local blink_cfg = (cfg.integrations or {}).blink or {}
  if blink_cfg.disable_in_masked == false then
    return
  end

  local state = require('camouflage.state')
  local masked = state.is_buffer_masked(bufnr)
    and parsers.is_supported(vim.api.nvim_buf_get_name(bufnr))

  if masked then
    if vim.b[bufnr].camouflage_blink_saved == nil then
      -- `false` records "there was nothing set", so the buffer goes back to
      -- blink's own default when masking stops.
      vim.b[bufnr].camouflage_blink_saved = vim.b[bufnr].completion == nil and 'unset'
        or tostring(vim.b[bufnr].completion)
    end
    vim.b[bufnr].completion = false
  elseif vim.b[bufnr].camouflage_blink_saved ~= nil then
    local saved = vim.b[bufnr].camouflage_blink_saved
    if saved == 'unset' then
      -- Deleting it puts the buffer back on blink's own default. `x and nil or
      -- y` would quietly write `y` here.
      vim.b[bufnr].completion = nil
    else
      vim.b[bufnr].completion = saved == 'true'
    end
    vim.b[bufnr].camouflage_blink_saved = nil
  end
end

M.sync_blink = sync_blink

---@return nil
local function setup_blink()
  if wrapped.blink or not pcall(require, 'blink.cmp') then
    return
  end
  local group = require('camouflage.state').augroup
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
    group = group,
    callback = function(args)
      sync_blink(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'CamouflageAfterDecorate', 'CamouflageConfigChanged' },
    callback = function()
      sync_blink(vim.api.nvim_get_current_buf())
    end,
  })
  wrapped.blink = true
end

---@return nil
function M.setup()
  local integrations = config.get().integrations or {}
  if integrations.fzf ~= false then
    setup_fzf()
  end
  if integrations.mini_pick ~= false then
    setup_mini_pick()
  end
  if (integrations.blink or {}).disable_in_masked ~= false then
    setup_blink()
  end
end

---Internal: forget the wrappers (used by tests).
---@return nil
function M._reset()
  wrapped = {}
end

return M
