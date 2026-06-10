---@mod camouflage.pwned.hash SHA-1 hash utilities
---@brief [[
--- Hashes secrets in-process via the vendored pure-Lua SHA-1 (no sha1sum /
--- openssl / shell), so the secret never appears on a process command line and
--- the HIBP check has no external tool dependency.
---@brief ]]

local M = {}

local sha1 = require('camouflage.pwned.sha1')

---Whether SHA-1 hashing is available.
---Always true: hashing is done in pure Lua with Neovim's guaranteed bit library.
---@return boolean
function M.is_available()
  return true
end

---@class Sha1Result
---@field hash string Full 40-char uppercase SHA-1 hash
---@field prefix string First 5 characters of hash
---@field suffix string Remaining 35 characters of hash

---Calculate the SHA-1 hash of a value.
---Hashing is synchronous and in-process; the callback is still scheduled (kept
---for API compatibility and to detach from any caller's fast event context).
---@param value string The value to hash
---@param callback fun(result: Sha1Result|nil) Called with result or nil on error
function M.sha1(value, callback)
  local wrapped_callback = vim.schedule_wrap(callback)

  local ok, hex = pcall(sha1.digest, value)
  if not ok or type(hex) ~= 'string' or #hex ~= 40 then
    wrapped_callback(nil)
    return
  end

  local hash = hex:upper()
  wrapped_callback({
    hash = hash,
    prefix = hash:sub(1, 5),
    suffix = hash:sub(6),
  })
end

return M
