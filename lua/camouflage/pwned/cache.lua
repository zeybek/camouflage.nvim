---@mod camouflage.pwned.cache Memory cache for pwned results
---@brief [[
--- Simple in-memory cache for HIBP check results.
--- Caches by full SHA-1 hash to avoid redundant API calls.
---@brief ]]

local M = {}

---@class PwnedCacheEntry
---@field pwned boolean Whether the password was found in breaches
---@field count number Number of times found in breaches (0 if not pwned)

---@type table<string, PwnedCacheEntry>
local cache = {}

---Get cached result for a hash
---@param hash string Full 40-char SHA-1 hash (uppercase)
---@return PwnedCacheEntry|nil
function M.get(hash)
  return cache[hash]
end

---Set cache entry
---@param hash string Full 40-char SHA-1 hash (uppercase)
---@param result PwnedCacheEntry
function M.set(hash, result)
  cache[hash] = result
end

---Clear all cache
function M.clear()
  cache = {}
end

---Get cache size
---@return number
function M.size()
  local count = 0
  for _ in pairs(cache) do
    count = count + 1
  end
  return count
end

return M
