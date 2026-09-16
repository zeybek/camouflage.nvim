---@mod camouflage.guard Mask changed rows before they are drawn

-- The decoration pass is debounced, and even with no debounce it runs through
-- vim.schedule, after Neovim has already redrawn the change. Until it runs, a
-- value that was just typed or pasted is on screen in plain text.
--
-- on_lines runs inside the change, before the redraw. From there the changed
-- rows get a provisional mask from a cheap line-level match, in a namespace of
-- their own, and the next decoration pass (which knows the real value ranges)
-- clears them. A provisional mask can briefly cover a value that the pass will
-- leave visible (a policy or hook exclusion), never the other way round.

local M = {}

local state = require('camouflage.state')
local config = require('camouflage.config')
local styles = require('camouflage.styles')
local parsers = require('camouflage.parsers')

M.namespace = vim.api.nvim_create_namespace('camouflage_guard')

---@type table<number, boolean>
local attached = {}

-- Patterns that find where the value starts on a single line. Each one captures
-- the position right after the separator and any opening quote.
local VALUE_START_PATTERNS = {
  -- KEY=value, export KEY=value, # KEY=value, key: value, - key: value
  '^%s*[#;]*%s*export%s+[%w_.%-]+%s*=%s*["\']?()',
  '^%s*[#;]*%s*%-?%s*["\']?[%w_.%-]+["\']?%s*[=:]%s*["\']?()',
  -- "any key": value
  '^%s*%-?%s*"[^"]*"%s*:%s*["\']?()',
  "^%s*%-?%s*'[^']*'%s*:%s*[\"']?()",
  -- Dockerfile ENV/ARG KEY=value and ENV KEY value
  '^%s*[Ee][Nn][Vv]%s+[%w_]+[=%s]%s*["\']?()',
  '^%s*[Aa][Rr][Gg]%s+[%w_]+=%s*["\']?()',
  -- <element attr="x">value
  '^%s*<[%w_.:%-]+[^>/]*>%s*()',
}

---Find the byte column (0-indexed) where a value starts on the line.
---@param line string
---@return number|nil
local function line_value_start(line)
  for _, pattern in ipairs(VALUE_START_PATTERNS) do
    local pos = line:match(pattern)
    if pos and pos <= #line then
      return pos - 1
    end
  end
  return nil
end

---Drop what follows a value on the same line: trailing space, a closing tag,
---a trailing comma and a closing quote.
---@param text string
---@return string
local function trim_value(text)
  local value = text:gsub('%s+$', ''):gsub('</[%w_.:%-]+>$', ''):gsub(',$', '')
  value = value:gsub('["\']$', '')
  return value
end

---Leftmost column covered by an existing mask on the row, if any.
---@param bufnr number
---@param row number 0-indexed
---@return number|nil
local function masked_start(bufnr, row)
  local ok, marks = pcall(
    vim.api.nvim_buf_get_extmarks,
    bufnr,
    state.namespace,
    { row, 0 },
    { row, -1 },
    {}
  )
  if not ok or #marks == 0 then
    return nil
  end
  local col
  for _, mark in ipairs(marks) do
    col = col and math.min(col, mark[3]) or mark[3]
  end
  return col
end

---@param cfg table
---@return string
local function highlight_group(cfg)
  return cfg.colors and 'CamouflageMask' or cfg.highlight_group
end

---Put provisional masks on rows [first, last) of the buffer.
---@param bufnr number
---@param first number 0-indexed, inclusive
---@param last number 0-indexed, exclusive
function M.mask_rows(bufnr, first, last)
  local cfg = config.get_for_buffer(bufnr)
  if not cfg.enabled then
    return
  end
  if cfg.max_lines and vim.api.nvim_buf_line_count(bufnr) > cfg.max_lines then
    return
  end

  pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, first, last)

  local revealed_row
  local ok_reveal, reveal = pcall(require, 'camouflage.reveal')
  if ok_reveal then
    local revealed = reveal.get_revealed()
    if revealed and revealed.bufnr == bufnr and revealed.line then
      revealed_row = revealed.line - 1
    end
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, first, last, false)
  local hl_group = highlight_group(cfg)

  for i, line in ipairs(lines) do
    local row = first + i - 1
    if row ~= revealed_row then
      local col = line_value_start(line) or masked_start(bufnr, row)
      if col and col < #line then
        local value = trim_value(line:sub(col + 1))
        if value ~= '' then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, M.namespace, row, col, {
            end_col = col + #value,
            virt_text = {
              {
                styles.generate_hidden_text(cfg.style, vim.fn.strdisplaywidth(value), value, cfg),
                hl_group,
              },
            },
            virt_text_pos = 'overlay',
            hl_mode = 'combine',
            -- above the pass's own masks, which a longer value outgrows
            priority = 102,
          })
        end
      end
    end
  end
end

---Remove every provisional mask from the buffer.
---@param bufnr number
function M.clear(bufnr)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, 0, -1)
end

---Start masking changed rows of a buffer as they change. Safe to call again.
---@param bufnr number
function M.attach(bufnr)
  if attached[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local ok = pcall(vim.api.nvim_buf_attach, bufnr, false, {
    on_lines = function(_, buf, _, first, _, last_new)
      -- Returning true detaches: the buffer is no longer tracked.
      if state.buffers[buf] == nil then
        attached[buf] = nil
        return true
      end
      if not parsers.is_supported(vim.api.nvim_buf_get_name(buf)) then
        return
      end
      M.mask_rows(buf, first, last_new)
    end,
    on_detach = function(_, buf)
      attached[buf] = nil
    end,
  })
  attached[bufnr] = ok or nil
end

---@param bufnr number
---@return boolean
function M.is_attached(bufnr)
  return attached[bufnr] == true
end

return M
