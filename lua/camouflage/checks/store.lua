---@mod camouflage.checks.store Per-buffer check result storage
---@brief [[
--- Stores check results keyed by (bufnr, line, check_name). Used as the
--- backing data for the badges renderer so multiple checks can render
--- side-by-side on the same line.
---@brief ]]

local M = {}

---@class CheckResult
---@field severity string '"error"' | '"warning"' | '"info"'
---@field text string Virtual text content (e.g. "PWNED 5x", "expires in 2h")
---@field hl_group? string Highlight for virtual text chunk
---@field sign_text? string Sign column text (max 2 chars)
---@field sign_hl? string Sign column highlight group
---@field line_hl? string Whole-line highlight group
---@field priority? integer Sort priority within virt_text array (higher = earlier)
---@field data? table Arbitrary payload for the check (used by refresh)

-- store[bufnr][lnum][check_name] = CheckResult
---@type table<integer, table<integer, table<string, CheckResult>>>
local store = {}

-- Results are keyed by line number, but lines move when text is inserted or
-- deleted above them. Each stored line gets an anchor extmark over its text;
-- sync() re-keys results to where the anchors are now, and drops results whose
-- line was deleted (Neovim 0.10+, where extmarks can be invalidated).
local anchor_ns = vim.api.nvim_create_namespace('camouflage_check_anchors')
-- anchors[bufnr][lnum] = extmark id
---@type table<integer, table<integer, integer>>
local anchors = {}

---@param bufnr integer
---@param lnum integer
local function ensure_anchor(bufnr, lnum)
  anchors[bufnr] = anchors[bufnr] or {}
  if anchors[bufnr][lnum] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if lnum < 0 or lnum >= vim.api.nvim_buf_line_count(bufnr) then
    return
  end
  local text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ''
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, anchor_ns, lnum, 0, {
    end_row = lnum,
    end_col = #text,
    invalidate = true,
  })
  if not ok then
    -- Neovim 0.9 has no `invalidate`: the anchor still follows the line.
    ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, anchor_ns, lnum, 0, {})
  end
  if ok then
    anchors[bufnr][lnum] = id
  end
end

---@param bufnr integer
---@param lnum integer
local function drop_anchor(bufnr, lnum)
  local id = anchors[bufnr] and anchors[bufnr][lnum]
  if not id then
    return
  end
  anchors[bufnr][lnum] = nil
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, anchor_ns, id)
  end
end

-- Changedtick of the last sync per buffer. Anchors only move when the text
-- moves, so between two ticks every anchor is still where the last sync left
-- it. Without this, a pass that stores n results walked all n anchors n times.
---@type table<integer, integer>
local synced_tick = {}

---Move stored results to the current line of their anchors.
---@param bufnr integer
local function sync(bufnr)
  local buf_anchors = anchors[bufnr]
  if not buf_anchors or not store[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if synced_tick[bufnr] == tick then
    return
  end
  synced_tick[bufnr] = tick

  local rows, changed = {}, false
  for lnum, id in pairs(buf_anchors) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, anchor_ns, id, { details = true })
    if not mark or not mark[1] or (mark[3] and mark[3].invalid) then
      rows[lnum] = false -- the line was deleted
      changed = true
    else
      rows[lnum] = mark[1]
      changed = changed or mark[1] ~= lnum
    end
  end
  if not changed then
    return
  end

  local new_store, new_anchors = {}, {}
  for lnum, results in pairs(store[bufnr]) do
    local row = rows[lnum]
    if row == nil then
      row = lnum -- no anchor (line was out of range when stored)
    end
    local id = buf_anchors[lnum]
    if row == false then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, anchor_ns, id)
    else
      new_store[row] = vim.tbl_extend('force', new_store[row] or {}, results)
      if id then
        if new_anchors[row] then
          pcall(vim.api.nvim_buf_del_extmark, bufnr, anchor_ns, id)
        else
          new_anchors[row] = id
        end
      end
    end
  end
  store[bufnr] = next(new_store) and new_store or nil
  anchors[bufnr] = new_anchors
end

M.sync = sync

---@param bufnr integer
---@param lnum integer 0-indexed
---@param check_name string
---@param result CheckResult|nil  nil clears this check's contribution
function M.set(bufnr, lnum, check_name, result)
  sync(bufnr)
  if result == nil then
    if store[bufnr] and store[bufnr][lnum] then
      store[bufnr][lnum][check_name] = nil
      if next(store[bufnr][lnum]) == nil then
        store[bufnr][lnum] = nil
        drop_anchor(bufnr, lnum)
      end
      if next(store[bufnr]) == nil then
        store[bufnr] = nil
      end
    end
    return
  end

  store[bufnr] = store[bufnr] or {}
  store[bufnr][lnum] = store[bufnr][lnum] or {}
  store[bufnr][lnum][check_name] = result
  ensure_anchor(bufnr, lnum)
end

---@param bufnr integer
---@param lnum integer
---@param check_name string
---@return CheckResult|nil
function M.get(bufnr, lnum, check_name)
  sync(bufnr)
  return store[bufnr] and store[bufnr][lnum] and store[bufnr][lnum][check_name] or nil
end

---@param bufnr integer
---@param lnum integer
---@return table<string, CheckResult>
function M.get_line(bufnr, lnum)
  sync(bufnr)
  return (store[bufnr] and store[bufnr][lnum]) or {}
end

---@param bufnr integer
---@return integer[] sorted line numbers with at least one result
function M.lines_with_results(bufnr)
  sync(bufnr)
  local lines = {}
  if not store[bufnr] then
    return lines
  end
  for lnum, _ in pairs(store[bufnr]) do
    table.insert(lines, lnum)
  end
  table.sort(lines)
  return lines
end

---Remove all results for a single line.
---@param bufnr integer
---@param lnum integer
function M.clear_line(bufnr, lnum)
  sync(bufnr)
  if store[bufnr] then
    store[bufnr][lnum] = nil
    drop_anchor(bufnr, lnum)
    if next(store[bufnr]) == nil then
      store[bufnr] = nil
    end
  end
end

---Remove all results contributed by a specific check across an entire buffer.
---@param bufnr integer
---@param check_name string
---@return integer[] lines that were affected (for re-rendering)
function M.clear_check(bufnr, check_name)
  sync(bufnr)
  local affected = {}
  if not store[bufnr] then
    return affected
  end
  for lnum, checks in pairs(store[bufnr]) do
    if checks[check_name] then
      checks[check_name] = nil
      table.insert(affected, lnum)
      if next(checks) == nil then
        store[bufnr][lnum] = nil
        drop_anchor(bufnr, lnum)
      end
    end
  end
  if next(store[bufnr]) == nil then
    store[bufnr] = nil
  end
  table.sort(affected)
  return affected
end

---@param bufnr integer
function M.clear_buffer(bufnr)
  store[bufnr] = nil
  anchors[bufnr] = nil
  synced_tick[bufnr] = nil
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, anchor_ns, 0, -1)
  end
end

---Internal: drop all state (used by tests).
function M._reset()
  store = {}
  anchors = {}
  synced_tick = {}
end

return M
