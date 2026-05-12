---@mod camouflage.checks Check aggregator (badges + per-line results)
---@brief [[
--- Central entry point for all value-level checks (pwned, jwt expiry, ...).
--- Each check writes a CheckResult per line via set_result; the badges
--- renderer composes a single end-of-line extmark from all results.
---@brief ]]

local M = {}

M.store = require('camouflage.checks.store')
M.badges = require('camouflage.checks.badges')

---Set or clear a check's result on a single line and re-render.
---@param bufnr integer
---@param lnum integer 0-indexed
---@param check_name string
---@param result CheckResult|nil  nil clears this check's contribution
function M.set_result(bufnr, lnum, check_name, result)
  M.store.set(bufnr, lnum, check_name, result)
  M.badges.render(bufnr, lnum)
end

---Clear all contributions from a single check across a buffer.
---@param bufnr integer
---@param check_name string
function M.clear_check(bufnr, check_name)
  local affected = M.store.clear_check(bufnr, check_name)
  for _, lnum in ipairs(affected) do
    M.badges.render(bufnr, lnum)
  end
end

---Clear everything (all checks, all lines) in a buffer.
---@param bufnr integer
function M.clear_buffer(bufnr)
  M.store.clear_buffer(bufnr)
  M.badges.clear_buffer(bufnr)
end

---Clear everything on a single line.
---@param bufnr integer
---@param lnum integer
function M.clear_line(bufnr, lnum)
  M.store.clear_line(bufnr, lnum)
  M.badges.clear_line(bufnr, lnum)
end

---Re-render all badge lines (useful after time-sensitive state changes
---like JWT expiry threshold crossings).
---@param bufnr integer
function M.render_buffer(bufnr)
  M.badges.render_buffer(bufnr)
end

return M
