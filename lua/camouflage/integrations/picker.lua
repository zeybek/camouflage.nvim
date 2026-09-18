---@mod camouflage.integrations.picker Mask values in picker result rows

-- Picker previews go through the normal decoration pass. The result rows do
-- not: a grep hit carries the matched line as text, and that text is drawn by
-- the picker itself. This masks the matched line of a row whose file a parser
-- handles, before the row reaches the list, so the value is never drawn.
--
-- The item keeps its real text, so opening the hit, yanking it or sending it to
-- the quickfix list all still work on the real line.

local M = {}

local config = require('camouflage.config')
local linemask = require('camouflage.linemask')
local parsers = require('camouflage.parsers')

---Masked version of a result row's text, or nil to leave the row alone.
---@param filename string|nil File the row points at
---@param text string|nil The matched line
---@return string|nil
function M.mask_result(filename, text)
  if type(filename) ~= 'string' or type(text) ~= 'string' or text == '' then
    return nil
  end
  local cfg = config.get()
  if not cfg.enabled or not (cfg.integrations and cfg.integrations.picker_results) then
    return nil
  end
  if not parsers.is_supported(filename) then
    return nil
  end
  return linemask.mask_line(text, cfg)
end

---Absolute-ish path of a snacks item, which can be relative to the picker cwd.
---@param item table
---@return string|nil
local function item_file(item)
  local file = item.file or item.path or item.filename
  if type(file) ~= 'string' or file == '' then
    return nil
  end
  if file:sub(1, 1) ~= '/' then
    local cwd = item.cwd or vim.fn.getcwd()
    file = cwd .. '/' .. file
  end
  return file
end

---@type boolean
local snacks_wrapped = false

---Wrap the snacks file formatter. Every source that shows a matched line
---(grep, grep_word, grep_buffers, lines) formats through it.
---
---The mask has to happen here rather than in `transform`: at transform time the
---grep source hasn't filled `item.line` yet.
---@return nil
local function setup_snacks()
  local ok, format = pcall(require, 'snacks.picker.format')
  if not ok or type(format.file) ~= 'function' or snacks_wrapped then
    return
  end
  local original = format.file
  format.file = function(item, picker)
    if type(item) == 'table' and type(item.line) == 'string' then
      local masked = M.mask_result(item_file(item), item.line)
      if masked then
        -- Format a copy, so the item the picker acts on keeps the real line.
        -- Match positions are dropped with it: they point into the old text and
        -- would highlight the middle of the mask.
        local copy = setmetatable({}, getmetatable(item))
        for key, value in pairs(item) do
          copy[key] = value
        end
        copy.line, copy.text, copy.positions = masked, masked, nil
        item = copy
      end
    end
    return original(item, picker)
  end
  snacks_wrapped = true
end

---@type boolean
local telescope_wrapped = false

---Wrap telescope's vimgrep entry maker so the matched line is masked in the
---results window.
---@return nil
local function setup_telescope()
  local ok, make_entry = pcall(require, 'telescope.make_entry')
  if not ok or type(make_entry.gen_from_vimgrep) ~= 'function' or telescope_wrapped then
    return
  end
  local original = make_entry.gen_from_vimgrep
  make_entry.gen_from_vimgrep = function(opts)
    local entry_maker = original(opts)
    return function(line)
      local entry = entry_maker(line)
      if type(entry) ~= 'table' or type(entry.text) ~= 'string' then
        return entry
      end
      local masked = M.mask_result(entry.filename, entry.text)
      if masked then
        entry.text = masked
      end
      return entry
    end
  end
  telescope_wrapped = true
end

---Install the hooks of every picker that is installed.
---@return nil
function M.setup()
  setup_snacks()
  setup_telescope()
end

---Internal: forget the wrappers (used by tests).
---@return nil
function M._reset()
  snacks_wrapped = false
  telescope_wrapped = false
end

return M
