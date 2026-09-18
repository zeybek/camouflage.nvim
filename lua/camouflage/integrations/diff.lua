---@mod camouflage.integrations.diff Mask values in diff and commit buffers

-- A diff of a `.env` puts the old and the new value side by side. The file is
-- masked, the diff of the same file was not, and `git commit -v` shows that
-- diff under the message every time a config file changes.
--
-- Which file a line belongs to comes from the hunk header above it, so a row is
-- only masked when the last header named a file a parser handles. Everything
-- else in the buffer, the message, the stat block, a diff of a source file, is
-- left alone.
--
-- Drawn from a decoration provider, so it follows a buffer that is rewritten
-- under the window (staging a hunk, `:Git diff --cached`) with nothing to hook.

local M = {}

local config = require('camouflage.config')
local linemask = require('camouflage.linemask')
local parsers = require('camouflage.parsers')
local styles = require('camouflage.styles')

M.namespace = vim.api.nvim_create_namespace('camouflage_diff')

-- Filetypes whose buffers hold unified diff text.
local FILETYPES = { diff = true, gitcommit = true, git = true, fugitive = true }

-- How far back a row looks for the header that names its file.
local HEADER_SCAN_LIMIT = 4000

---@type table|nil
local current

---@param cfg table
---@return string
local function highlight_group(cfg)
  return cfg.colors and 'CamouflageMask' or cfg.highlight_group
end

---The file a header line names, if it is one.
---@param line string
---@return string|nil file
---@return boolean is_header true for any header, even one without a usable file
function M.header_file(line)
  local git = line:match('^diff %-%-git a/.* b/(.*)$')
  if git then
    return git, true
  end
  if line:match('^diff ') then
    return nil, true
  end
  local plus = line:match('^%+%+%+ b/(.*)$') or line:match('^%+%+%+ (.*)$')
  if plus then
    if plus == '/dev/null' then
      return nil, true
    end
    -- `+++ b/file.env	2026-09-18 ...` in a plain unified diff
    return (plus:gsub('\t.*$', '')), true
  end
  if line:match('^%-%-%- ') then
    return nil, true
  end
  return nil, false
end

---The file the rows around `row` belong to.
---@param bufnr number
---@param row number 0-indexed
---@return string|nil
function M.file_at(bufnr, row)
  local first = math.max(0, row - HEADER_SCAN_LIMIT)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first, row + 1, false)
  for i = #lines, 1, -1 do
    local file, is_header = M.header_file(lines[i])
    if is_header then
      if file then
        return file
      end
      -- A `diff --git` line with no usable name, or /dev/null: nothing to mask
      -- until the next header.
      if lines[i]:match('^diff ') or lines[i]:match('^%+%+%+ ') then
        return nil
      end
    end
  end
  return nil
end

---The part of a diff row that should be covered, if any.
---@param line string
---@return number|nil col 0-indexed byte column
---@return string|nil value
function M.row_value(line)
  -- Content rows are ' ', '+' and '-' followed by the file's own text. Headers
  -- start with the same characters tripled, and are skipped by header_file.
  local marker = line:sub(1, 1)
  if marker ~= ' ' and marker ~= '+' and marker ~= '-' then
    return nil, nil
  end
  if select(2, M.header_file(line)) then
    return nil, nil
  end
  local col, value = linemask.find_value(line:sub(2))
  if not col then
    return nil, nil
  end
  return col + 1, value
end

---@return boolean
local function enabled()
  local cfg = config.get()
  return cfg.enabled and (cfg.integrations and cfg.integrations.diff) == true
end

---Whether a buffer's rows are diff text at all.
---@param bufnr number
---@return boolean
function M.is_diff_buffer(bufnr)
  return FILETYPES[vim.bo[bufnr].filetype] == true
end

---Picks up the state the rows of a window are drawn with. Public so it can be
---tested without a redraw.
---@param bufnr number
---@param topline number 0-indexed first visible row
---@return boolean
function M.on_win(bufnr, topline)
  current = nil
  if not enabled() or not M.is_diff_buffer(bufnr) then
    return false
  end
  local file = M.file_at(bufnr, topline)
  current = {
    cfg = config.get(),
    supported = file ~= nil and parsers.is_supported(file),
  }
  return true
end

---Masks one row while the window is drawn. Returns what it covered, which is
---what the tests assert on, since ephemeral marks only exist during a redraw.
---@param bufnr number
---@param row number
---@return number|nil col
---@return string|nil value
function M.on_line(bufnr, row)
  if not current then
    return nil, nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then
    return nil, nil
  end

  -- Headers passing by keep the file up to date while the window is drawn.
  local file, is_header = M.header_file(line)
  if is_header then
    current.supported = file ~= nil and parsers.is_supported(file)
    return nil, nil
  end
  if not current.supported then
    return nil, nil
  end

  local col, value = M.row_value(line)
  if not col or not value then
    return nil, nil
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
  return col, value
end

---@return nil
function M.setup()
  vim.api.nvim_set_decoration_provider(M.namespace, {
    on_win = function(_, _, bufnr, topline)
      return M.on_win(bufnr, topline)
    end,
    on_line = function(_, _, bufnr, row)
      M.on_line(bufnr, row)
    end,
  })
end

---Internal: drop the per-redraw state (used by tests).
---@return nil
function M._reset()
  current = nil
end

return M
