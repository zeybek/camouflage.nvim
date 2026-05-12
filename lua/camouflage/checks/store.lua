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

---@param bufnr integer
---@param lnum integer 0-indexed
---@param check_name string
---@param result CheckResult|nil  nil clears this check's contribution
function M.set(bufnr, lnum, check_name, result)
  if result == nil then
    if store[bufnr] and store[bufnr][lnum] then
      store[bufnr][lnum][check_name] = nil
      if next(store[bufnr][lnum]) == nil then
        store[bufnr][lnum] = nil
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
end

---@param bufnr integer
---@param lnum integer
---@param check_name string
---@return CheckResult|nil
function M.get(bufnr, lnum, check_name)
  return store[bufnr] and store[bufnr][lnum] and store[bufnr][lnum][check_name] or nil
end

---@param bufnr integer
---@param lnum integer
---@return table<string, CheckResult>
function M.get_line(bufnr, lnum)
  return (store[bufnr] and store[bufnr][lnum]) or {}
end

---@param bufnr integer
---@return integer[] sorted line numbers with at least one result
function M.lines_with_results(bufnr)
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
  if store[bufnr] then
    store[bufnr][lnum] = nil
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
end

---Internal: drop all state (used by tests).
function M._reset()
  store = {}
end

return M
