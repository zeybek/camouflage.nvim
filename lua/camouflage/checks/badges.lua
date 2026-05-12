---@mod camouflage.checks.badges Badge renderer
---@brief [[
--- Composes a single end-of-line extmark per buffer line from all check
--- results held in camouflage.checks.store. Multiple checks render
--- side-by-side as separate virt_text chunks; the highest-severity check
--- wins for sign column and line highlight (only one of each is possible
--- per line).
---@brief ]]

local M = {}

local store = require('camouflage.checks.store')

local ns_id = vim.api.nvim_create_namespace('camouflage_badges')

---@return { position: string, separator: string, separator_hl: string }
local function get_badges_config()
  local ok, cfg = pcall(function()
    return require('camouflage.config').get()
  end)
  local b = (ok and cfg and cfg.checks and cfg.checks.badges) or {}
  return {
    position = b.position or 'right_align',
    separator = b.separator or ' ',
    separator_hl = b.separator_hl or 'Comment',
  }
end

-- Order in which checks appear in the badge bar (left → right).
-- Unlisted checks render after these, alphabetically.
local CHECK_ORDER = { 'pwned', 'expiry' }

local SEVERITY_RANK = { error = 3, warning = 2, info = 1 }

---@return integer
function M.get_namespace()
  return ns_id
end

---Return the index of a check name in CHECK_ORDER, or a large number if missing.
---@param name string
---@return integer
local function order_index(name)
  for i, n in ipairs(CHECK_ORDER) do
    if n == name then
      return i
    end
  end
  return 100
end

---Sort check names by render order (CHECK_ORDER first, then alphabetic).
---@param names string[]
---@return string[]
local function sort_check_names(names)
  table.sort(names, function(a, b)
    local ia, ib = order_index(a), order_index(b)
    if ia ~= ib then
      return ia < ib
    end
    return a < b
  end)
  return names
end

---Render badges for a single line. Replaces any existing extmark on this line.
---@param bufnr integer
---@param lnum integer 0-indexed
function M.render(bufnr, lnum)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if lnum < 0 or lnum >= line_count then
    return
  end

  -- Always clear any existing mark on this line so we render fresh.
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, lnum, lnum + 1)

  local results = store.get_line(bufnr, lnum)
  local names = {}
  for name, _ in pairs(results) do
    table.insert(names, name)
  end
  if #names == 0 then
    return
  end
  sort_check_names(names)

  local badges_cfg = get_badges_config()

  -- Compose virt_text and determine winning sign/line_hl.
  local virt_text = {}
  local winning_severity, winning_sign, winning_sign_hl, winning_line_hl = -1, nil, nil, nil
  local chunks_added = 0

  for _, name in ipairs(names) do
    local r = results[name]
    if r.text and r.text ~= '' then
      if chunks_added > 0 then
        table.insert(virt_text, { badges_cfg.separator, badges_cfg.separator_hl })
      end
      table.insert(virt_text, { r.text, r.hl_group or 'Comment' })
      chunks_added = chunks_added + 1
    end

    local sev = SEVERITY_RANK[r.severity] or 0
    if sev > winning_severity then
      winning_severity = sev
      if r.sign_text then
        winning_sign = r.sign_text
        winning_sign_hl = r.sign_hl
      end
      if r.line_hl then
        winning_line_hl = r.line_hl
      end
    end
  end

  ---@type vim.api.keyset.set_extmark
  local opts = {
    id = lnum + 1,
    priority = 200,
  }
  if #virt_text > 0 then
    opts.virt_text = virt_text
    opts.virt_text_pos = badges_cfg.position
  end
  if winning_sign then
    opts.sign_text = winning_sign
    opts.sign_hl_group = winning_sign_hl
  end
  if winning_line_hl then
    opts.line_hl_group = winning_line_hl
  end

  -- Only call set_extmark if at least one decoration is present.
  if opts.virt_text or opts.sign_text or opts.line_hl_group then
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, lnum, 0, opts)
  end
end

---Re-render every line in the buffer that currently has results.
---@param bufnr integer
function M.render_buffer(bufnr)
  for _, lnum in ipairs(store.lines_with_results(bufnr)) do
    M.render(bufnr, lnum)
  end
end

---Clear the badge extmark on a line without touching the store.
---@param bufnr integer
---@param lnum integer
function M.clear_line(bufnr, lnum)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, lnum, lnum + 1)
  end
end

---Clear all badge extmarks for a buffer.
---@param bufnr integer
function M.clear_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  end
end

return M
