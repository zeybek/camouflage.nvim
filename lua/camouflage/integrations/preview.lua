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
---@return boolean installed
local function setup_fzf()
  if wrapped.fzf then
    return true
  end
  local ok, builtin = pcall(require, 'fzf-lua.previewer.builtin')
  if not ok or type(builtin) ~= 'table' or type(builtin.buffer_or_file) ~= 'table' then
    return false
  end
  local original = builtin.buffer_or_file.preview_buf_post
  if type(original) ~= 'function' then
    return false
  end

  builtin.buffer_or_file.preview_buf_post = function(self, entry, ...)
    local result = original(self, entry, ...)
    local path = entry and (entry.path or entry.bufname or entry.uri)
    M.mask_buffer(self and self.preview_bufnr, path)
    return result
  end
  wrapped.fzf = true
  return true
end

---The file a mini.pick item points at. A string item can carry a position
---after the path, split by NUL characters ("path\0lnum\0col\0text" for grep),
---which mini.pick cuts off the same way. A buffer item gives its buffer's name.
---@param item any
---@return string|nil
function M.mini_pick_item_path(item)
  local path
  if type(item) == 'table' then
    path = item.path or item.text
    local buf = item.bufnr or item.buf_id or item.buf
    if not path and type(buf) == 'number' and vim.api.nvim_buf_is_valid(buf) then
      path = vim.api.nvim_buf_get_name(buf)
    end
  else
    path = item
  end
  if type(path) ~= 'string' then
    return nil
  end
  path = path:match('^[^%z]*')
  return path ~= '' and path or nil
end

-- Defined below, next to the row masking it shares its logic with.
local mask_mini_pick_title

-- Preview functions that already mask, so nothing gets wrapped twice.
---@type table<function, boolean>
local mini_pick_wrappers = setmetatable({}, { __mode = 'k' })

---A mini.pick preview function that masks what `preview` draws.
---@param preview function
---@return function
local function wrap_mini_pick_preview(preview)
  if mini_pick_wrappers[preview] then
    return preview
  end
  local wrapper = function(buf_id, item, opts)
    local result = preview(buf_id, item, opts)
    M.mask_buffer(buf_id, M.mini_pick_item_path(item))
    mask_mini_pick_title(item)
    return result
  end
  mini_pick_wrappers[wrapper] = true
  return wrapper
end

M.mini_pick_namespace = vim.api.nvim_create_namespace('camouflage_mini_pick')

-- mini.pick shows the NUL separators of an item ("path\0lnum\0col\0text")
-- as this character.
local MINI_PICK_SEP = '│'

---Where the value sits in a row mini.pick drew for `item`, if the item points
---into a file a parser handles and its text carries a value. The text is what
---follows the last separator, so a grep row "prod.env│1│1│API_KEY=secret"
---yields the range of `secret`.
---@param line string
---@param item any
---@return number|nil col 0-indexed byte column
---@return number|nil len
function M.mini_pick_row_value(line, item)
  local cfg = config.get()
  local integrations = cfg.integrations or {}
  if not cfg.enabled or integrations.picker_results == false or integrations.mini_pick == false then
    return nil, nil
  end
  local path = M.mini_pick_item_path(item)
  if not path or not parsers.is_supported(path) then
    return nil, nil
  end
  local last
  local init = 1
  while true do
    local at = line:find(MINI_PICK_SEP, init, true)
    if not at then
      break
    end
    last = at
    init = at + #MINI_PICK_SEP
  end
  if not last then
    return nil, nil
  end
  local text_start = last + #MINI_PICK_SEP
  local col, value = require('camouflage.linemask').find_value(line:sub(text_start))
  if not col then
    return nil, nil
  end
  return text_start - 1 + col, #value
end

---Cover the values in the rows mini.pick just drew. The items keep their real
---text, so choosing a row still jumps to the real line.
---@param buf_id number
---@param items any[]
function M.mask_mini_pick_rows(buf_id, items)
  if not vim.api.nvim_buf_is_valid(buf_id) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf_id, M.mini_pick_namespace, 0, -1)
  local cfg = config.get()
  local styles = require('camouflage.styles')
  local hl = cfg.colors and 'CamouflageMask' or cfg.highlight_group
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, #items, false)
  for i, line in ipairs(lines) do
    local col, len = M.mini_pick_row_value(line, items[i])
    if col then
      local value = line:sub(col + 1, col + len)
      pcall(vim.api.nvim_buf_set_extmark, buf_id, M.mini_pick_namespace, i - 1, col, {
        end_col = col + len,
        virt_text = {
          { styles.generate_hidden_text(cfg.style, vim.fn.strdisplaywidth(value), value, cfg), hl },
        },
        virt_text_pos = 'overlay',
        hl_mode = 'combine',
        priority = 200,
      })
    end
  end
end

---mini.pick titles the preview window with the current row's text. Once the
---preview is drawn, cover the value there too.
---@param item any
mask_mini_pick_title = function(item)
  vim.schedule(function()
    local pick = package.loaded['mini.pick']
    local ok, picker = pcall(function()
      return pick.get_picker_state()
    end)
    local win = ok and picker and picker.windows and picker.windows.main
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end
    local win_cfg = vim.api.nvim_win_get_config(win)
    if type(win_cfg.title) ~= 'table' then
      return
    end
    local changed = false
    local title = {}
    for _, chunk in ipairs(win_cfg.title) do
      local text, hl = chunk[1], chunk[2]
      local col, len = M.mini_pick_row_value(text, item)
      if col then
        local cfg = config.get()
        local value = text:sub(col + 1, col + len)
        local mask = require('camouflage.styles').generate_hidden_text(
          cfg.style,
          vim.fn.strdisplaywidth(value),
          value,
          cfg
        )
        text = text:sub(1, col) .. mask .. text:sub(col + len + 1)
        changed = true
      end
      table.insert(title, { text, hl })
    end
    if changed then
      pcall(vim.api.nvim_win_set_config, win, { title = title, title_pos = win_cfg.title_pos })
    end
  end)
end

---A mini.pick show function that masks the rows `show` draws.
---@param show function
---@return function
local function wrap_mini_pick_show(show)
  if mini_pick_wrappers[show] then
    return show
  end
  local wrapper = function(buf_id, items, query, opts)
    local result = show(buf_id, items, query, opts)
    M.mask_mini_pick_rows(buf_id, items or {})
    return result
  end
  mini_pick_wrappers[wrapper] = true
  return wrapper
end

---mini.pick renders every preview through one function.
---@return nil
---@return boolean installed
local function setup_mini_pick()
  if wrapped.mini_pick then
    return true
  end
  local ok, pick = pcall(require, 'mini.pick')
  if not ok or type(pick) ~= 'table' or type(pick.default_preview) ~= 'function' then
    return false
  end

  pick.default_preview = wrap_mini_pick_preview(pick.default_preview)
  if type(pick.default_show) == 'function' then
    pick.default_show = wrap_mini_pick_show(pick.default_show)
  end
  wrapped.mini_pick = true
  return true
end

---A picker copies `MiniPick.default_preview` into its source when it starts,
---so one started before the hook above was installed (mini.pick loaded after
---camouflage) keeps the plain function, and so does a picker with a preview of
---its own. MiniPickStart comes right after the start: wrap whatever preview the
---active picker ended up with.
---@return nil
function M.on_mini_pick_start()
  local pick = package.loaded['mini.pick']
  if type(pick) ~= 'table' or type(pick.get_picker_opts) ~= 'function' then
    return
  end
  if (config.get().integrations or {}).mini_pick == false then
    return
  end
  local source = (pick.get_picker_opts() or {}).source or {}
  local update = {}
  if type(source.preview) == 'function' and not mini_pick_wrappers[source.preview] then
    update.preview = wrap_mini_pick_preview(source.preview)
  end
  if type(source.show) == 'function' and not mini_pick_wrappers[source.show] then
    update.show = wrap_mini_pick_show(source.show)
  end
  if next(update) then
    pick.set_picker_opts({ source = update })
  end
end

---@type number|nil
local mini_pick_start_autocmd

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

---@type number[]
local blink_autocmds = {}

---blink has nothing to wrap, only autocmds, so this recreates them on every
---call instead of stopping at a "done once" flag: whatever cleared them (a
---config reload) is followed by this setup again.
---@param enabled boolean
---@return nil
local function setup_blink(enabled)
  for _, id in ipairs(blink_autocmds) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  blink_autocmds = {}
  if not enabled or not pcall(require, 'blink.cmp') then
    return
  end
  local group = require('camouflage.state').integrations_augroup
  table.insert(
    blink_autocmds,
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
      group = group,
      callback = function(args)
        sync_blink(args.buf)
      end,
    })
  )
  table.insert(
    blink_autocmds,
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = { 'CamouflageAfterDecorate', 'CamouflageConfigChanged' },
      callback = function()
        sync_blink(vim.api.nvim_get_current_buf())
      end,
    })
  )
end

---@return nil
function M.setup()
  local integrations = config.get().integrations or {}
  local later = require('camouflage.integrations.later')
  if integrations.fzf ~= false then
    later.add('preview.fzf', { module = 'fzf-lua.previewer.builtin', install = setup_fzf })
  else
    later.remove('preview.fzf')
  end
  if mini_pick_start_autocmd then
    pcall(vim.api.nvim_del_autocmd, mini_pick_start_autocmd)
    mini_pick_start_autocmd = nil
  end
  if integrations.mini_pick ~= false then
    later.add('preview.mini_pick', { module = 'mini.pick', install = setup_mini_pick })
    mini_pick_start_autocmd = vim.api.nvim_create_autocmd('User', {
      group = require('camouflage.state').integrations_augroup,
      pattern = 'MiniPickStart',
      callback = function()
        M.on_mini_pick_start()
      end,
    })
  else
    later.remove('preview.mini_pick')
  end
  setup_blink((integrations.blink or {}).disable_in_masked ~= false)
end

---Internal: forget the wrappers (used by tests).
---@return nil
function M._reset()
  wrapped = {}
end

return M
