---@mod camouflage.integrations.quickfix Mask values in quickfix and location lists

-- A quickfix row carries the matched line of the file it points at, so a list
-- built from a grep over a `.env` shows the values in a window that sits next
-- to the code. `:CamouflageAudit` never puts a value in the list, but a list the
-- user built themselves gets no masking at all.
--
-- The masks are drawn from a decoration provider, so they cover whatever the
-- list holds at that moment: a new grep, `:cnewer`, a filtered list, all of it
-- without an event to hook. Only the rows on screen are looked at, and the list
-- itself keeps the real text, which `:cnext`, `:cdo` and copying a row need.

local M = {}

local config = require('camouflage.config')
local linemask = require('camouflage.linemask')
local parsers = require('camouflage.parsers')
local styles = require('camouflage.styles')

M.namespace = vim.api.nvim_create_namespace('camouflage_quickfix')

-- What the current window's rows are drawn from, filled in on_win.
---@type table|nil
local current

---@param cfg table
---@return string
local function highlight_group(cfg)
  return cfg.colors and 'CamouflageMask' or cfg.highlight_group
end

---Items of the list a window shows, quickfix or location.
---@param winid number
---@return table[]|nil
function M.list_items(winid)
  local info = (vim.fn.getwininfo(winid) or {})[1]
  if not info or info.quickfix ~= 1 then
    return nil
  end
  local ok, list
  if info.loclist == 1 then
    ok, list = pcall(vim.fn.getloclist, winid, { items = 0 })
  else
    ok, list = pcall(vim.fn.getqflist, { items = 0 })
  end
  return ok and list and list.items or nil
end

---Where the item's text starts on its row. Rows are `file|lnum col N| text`,
---and a file name can contain a bar, so the item's own text is looked up first.
---@param line string
---@param item table
---@return number|nil 0-indexed byte column
local function text_start(line, item)
  local text = item.text and vim.trim(item.text) or ''
  if text ~= '' then
    local found = line:find(text, 1, true)
    if found then
      return found - 1
    end
  end
  local _, bars = line:find('|[^|]*|')
  if bars then
    local rest = line:sub(bars + 1)
    return bars + #(rest:match('^%s*') or '')
  end
  return nil
end

---The part of a row that should be covered, if any.
---@param line string Row as drawn
---@param item table|nil List item the row was drawn from
---@return number|nil col 0-indexed byte column
---@return string|nil value
function M.row_value(line, item)
  local bufname = item
    and item.bufnr
    and item.bufnr > 0
    and vim.api.nvim_buf_is_valid(item.bufnr)
    and vim.api.nvim_buf_get_name(item.bufnr)
  if not bufname or bufname == '' or not parsers.is_supported(bufname) then
    return nil, nil
  end
  local offset = text_start(line, item)
  if not offset then
    return nil, nil
  end
  local col, value = linemask.find_value(line:sub(offset + 1))
  if not col then
    return nil, nil
  end
  return offset + col, value
end

---@return boolean
local function enabled()
  local cfg = config.get()
  return cfg.enabled and (cfg.integrations and cfg.integrations.quickfix) == true
end

---Decides whether a window's rows need masking, and picks up the list they are
---drawn from. Public so it can be tested without a redraw.
---@param winid number
---@param bufnr number
---@return boolean
function M.on_win(winid, bufnr)
  current = nil
  if not enabled() or vim.bo[bufnr].buftype ~= 'quickfix' then
    return false
  end
  local items = M.list_items(winid)
  if not items or #items == 0 then
    return false
  end
  current = { items = items, cfg = config.get() }
  return true
end

---@return nil
function M.setup()
  vim.api.nvim_set_decoration_provider(M.namespace, {
    on_win = function(_, winid, bufnr)
      return M.on_win(winid, bufnr)
    end,
    on_line = function(_, _, bufnr, row)
      if not current then
        return
      end
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if not line then
        return
      end
      local col, value = M.row_value(line, current.items[row + 1])
      if not col or not value then
        return
      end
      local cfg = current.cfg
      pcall(vim.api.nvim_buf_set_extmark, bufnr, M.namespace, row, col, {
        end_col = col + #value,
        virt_text = {
          {
            styles.generate_hidden_text(cfg.style, vim.fn.strdisplaywidth(value), value, cfg),
            highlight_group(cfg),
          },
        },
        virt_text_pos = 'overlay',
        hl_mode = 'combine',
        ephemeral = true,
      })
    end,
  })
end

---Internal: drop the per-redraw state (used by tests).
---@return nil
function M._reset()
  current = nil
end

return M
