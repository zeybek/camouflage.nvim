---@mod camouflage.checks.memo Per-buffer memo for check work

-- A decoration pass runs again every time you stop typing, over values that
-- mostly didn't change, and the checks redo their work for each one. Entropy
-- scoring and JWT decoding are the expensive parts, and both depend only on the
-- value and the config, so the answer can be kept.
--
-- The memo lives per buffer and dies with it, so it holds nothing longer than
-- the parsed variables already do, and it is dropped whenever the config
-- generation moves so a changed threshold takes effect at once.

local M = {}

-- Enough for a large file, and a cheap ceiling: past it the buffer's memo is
-- dropped rather than evicted entry by entry.
local MAX_ENTRIES = 4096

---@type table<integer, { generation: integer, entries: table<string, any>, count: integer }>
local store = {}

---@param bufnr integer
---@param generation integer
---@return table
local function bucket(bufnr, generation)
  local current = store[bufnr]
  if not current or current.generation ~= generation then
    current = { generation = generation, entries = {}, count = 0 }
    store[bufnr] = current
  end
  return current
end

---Answer for `key`, computing and keeping it on the first call.
---
---`compute` may return nil, which is remembered too: "this value has nothing to
---report" is the common answer and worth not recomputing.
---@param bufnr integer
---@param generation integer Config generation the answer belongs to
---@param key string
---@param compute fun(): any
---@return any
function M.get(bufnr, generation, key, compute)
  local current = bucket(bufnr, generation)
  local hit = current.entries[key]
  if hit ~= nil then
    if hit == vim.NIL then
      return nil
    end
    return hit
  end

  local value = compute()
  if current.count >= MAX_ENTRIES then
    current.entries, current.count = {}, 0
  end
  current.entries[key] = value == nil and vim.NIL or value
  current.count = current.count + 1
  return value
end

---@param bufnr integer
function M.clear(bufnr)
  store[bufnr] = nil
end

---Internal: drop everything (used by tests).
function M.clear_all()
  store = {}
end

---Internal: how many answers are held for a buffer (used by tests).
---@param bufnr integer
---@return integer
function M.count(bufnr)
  return store[bufnr] and store[bufnr].count or 0
end

return M
