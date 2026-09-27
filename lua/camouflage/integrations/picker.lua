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
---@return boolean installed
local function setup_snacks()
  if snacks_wrapped then
    return true
  end
  local ok, format = pcall(require, 'snacks.picker.format')
  if not ok or type(format) ~= 'table' or type(format.file) ~= 'function' then
    return false
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
  return true
end

---@type boolean
local telescope_wrapped = false

---Wrap telescope's vimgrep entry maker so the matched line is masked in the
---results window.
---@return nil
---@return boolean installed
local function setup_telescope()
  if telescope_wrapped then
    return true
  end
  local ok, make_entry = pcall(require, 'telescope.make_entry')
  if not ok or type(make_entry) ~= 'table' or type(make_entry.gen_from_vimgrep) ~= 'function' then
    return false
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
  return true
end

M.fzf_namespace = vim.api.nvim_create_namespace('camouflage_fzf')

---Where the value sits in a row of an fzf list, if the row reads
---`<path>:<line>[:<col>]:<text>` (with an optional icon or pointer in front)
---and the path is a file a parser handles.
---@param line string
---@return number|nil col 0-indexed byte column
---@return number|nil len
function M.fzf_row_value(line)
  local cfg = config.get()
  local integrations = cfg.integrations or {}
  if not cfg.enabled or integrations.picker_results == false or integrations.fzf == false then
    return nil, nil
  end
  local path, text_start = line:match('([^%s:]+):%d+:%d+:()')
  if not path then
    path, text_start = line:match('([^%s:]+):%d+:()')
  end
  if not path or not parsers.is_supported(path) then
    return nil, nil
  end
  local col, value = linemask.find_value(line:sub(text_start))
  if not col then
    return nil, nil
  end
  return text_start - 1 + col, #value
end

---fzf-lua draws its list in a terminal buffer (filetype `fzf`) that fzf itself
---renders, so there is no Lua function per row to wrap. The rows are masked
---while they are drawn instead, like terminal output, and only the rows on
---screen are looked at.
---@return nil
local function setup_fzf_rows()
  vim.api.nvim_set_decoration_provider(M.fzf_namespace, {
    on_win = function(_, _, bufnr)
      return vim.bo[bufnr].filetype == 'fzf'
    end,
    on_line = function(_, _, bufnr, row)
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if not line then
        return
      end
      local col, len = M.fzf_row_value(line)
      if not col then
        return
      end
      local cfg = config.get()
      local value = line:sub(col + 1, col + len)
      pcall(vim.api.nvim_buf_set_extmark, bufnr, M.fzf_namespace, row, col, {
        end_col = col + len,
        virt_text = {
          {
            require('camouflage.styles').generate_hidden_text(
              cfg.style,
              vim.fn.strdisplaywidth(value),
              value,
              cfg
            ),
            cfg.colors and 'CamouflageMask' or cfg.highlight_group,
          },
        },
        virt_text_pos = 'overlay',
        hl_mode = 'combine',
        ephemeral = true,
      })
    end,
  })
end

---Install the hooks of every picker, now or once the picker is loaded.
---@return nil
function M.setup()
  setup_fzf_rows()
  local later = require('camouflage.integrations.later')
  later.add('picker_results.snacks', { module = 'snacks.picker.format', install = setup_snacks })
  later.add(
    'picker_results.telescope',
    { module = 'telescope.make_entry', install = setup_telescope }
  )
end

---Internal: forget the wrappers (used by tests).
---@return nil
function M._reset()
  snacks_wrapped = false
  telescope_wrapped = false
end

return M
