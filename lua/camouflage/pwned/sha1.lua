---@mod camouflage.pwned.sha1 Pure-Lua SHA-1
---@brief [[
--- A small, dependency-free SHA-1 used by the HIBP k-anonymity check.
---
--- Hashing in-process (rather than shelling out to sha1sum/openssl) keeps the
--- secret off the process command line entirely — the previous implementation
--- base64-encoded the secret into an `sh -c` argv, where it was visible to any
--- local process via `ps`. It also removes the external tool dependency and the
--- per-variable process spawn, and works on Neovim 0.9+.
---
--- Uses LuaJIT's bit operations, which Neovim guarantees in every build
--- (a fallback is provided for PUC Lua); see |lua-luajit|.
---@brief ]]

local bit = require('bit')
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rol, tohex = bit.lshift, bit.rol, bit.tohex
local tobit = bit.tobit

local M = {}

-- 32-bit modular addition. Each operand is an int32 from a bit op or an init
-- constant < 2^32; the double sum of a few of these is exact, and tobit() wraps
-- it back to a signed int32 (i.e. mod 2^32).
local function add32(a, b)
  return tobit(a + b)
end

---Compute the SHA-1 digest of a byte string.
---@param message string
---@return string hex 40-character lowercase hex digest
function M.digest(message)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0

  local msg_len = #message
  local bits = msg_len * 8

  -- Padding: append 0x80, then 0x00 up to length ≡ 56 (mod 64), then the
  -- 64-bit big-endian message length in bits.
  local padded = { message, '\128' }
  local pad = (56 - (msg_len + 1) % 64) % 64
  padded[#padded + 1] = string.rep('\0', pad)
  for i = 7, 0, -1 do
    padded[#padded + 1] = string.char(math.floor(bits / 2 ^ (8 * i)) % 256)
  end
  message = table.concat(padded)

  local w = {}
  for chunk = 1, #message, 64 do
    for i = 0, 15 do
      local b = chunk + i * 4
      w[i] = bor(
        lshift(message:byte(b), 24),
        lshift(message:byte(b + 1), 16),
        lshift(message:byte(b + 2), 8),
        message:byte(b + 3)
      )
    end
    for i = 16, 79 do
      w[i] = rol(bxor(bxor(bxor(w[i - 3], w[i - 8]), w[i - 14]), w[i - 16]), 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then
        f = bor(band(b, c), band(bnot(b), d))
        k = 0x5A827999
      elseif i < 40 then
        f = bxor(bxor(b, c), d)
        k = 0x6ED9EBA1
      elseif i < 60 then
        f = bor(bor(band(b, c), band(b, d)), band(c, d))
        k = 0x8F1BBCDC
      else
        f = bxor(bxor(b, c), d)
        k = 0xCA62C1D6
      end

      local temp = add32(add32(add32(add32(rol(a, 5), f), e), k), w[i])
      e = d
      d = c
      c = rol(b, 30)
      b = a
      a = temp
    end

    h0 = add32(h0, a)
    h1 = add32(h1, b)
    h2 = add32(h2, c)
    h3 = add32(h3, d)
    h4 = add32(h4, e)
  end

  return tohex(h0) .. tohex(h1) .. tohex(h2) .. tohex(h3) .. tohex(h4)
end

return M
