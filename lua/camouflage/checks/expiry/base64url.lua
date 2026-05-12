---@mod camouflage.checks.expiry.base64url URL-safe base64 decode
---@brief [[
--- Minimal url-safe base64 decoder for JWT segments. JWT uses RFC 4648
--- "base64url" with '-' instead of '+' and '_' instead of '/', and
--- padding stripped. This module re-applies padding and delegates to
--- standard base64 when available.
---@brief ]]

local M = {}

local ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local INDEX = {}
for i = 1, #ALPHA do
  INDEX[ALPHA:sub(i, i)] = i - 1
end

---Convert url-safe base64 to standard base64 and reinstate padding.
---@param input string
---@return string
local function to_standard(input)
  local s = input:gsub('-', '+'):gsub('_', '/')
  local pad = (4 - (#s % 4)) % 4
  return s .. string.rep('=', pad)
end

---Decode standard base64 (with padding) to bytes.
---@param s string
---@return string|nil
local function decode_b64(s)
  -- Strip whitespace/padding for processing.
  local input = s:gsub('=+$', ''):gsub('%s+', '')
  if input:match('[^A-Za-z0-9+/]') then
    return nil
  end

  local out = {}
  local buf, bits = 0, 0
  for i = 1, #input do
    local c = input:sub(i, i)
    local v = INDEX[c]
    if not v then
      return nil
    end
    buf = buf * 64 + v
    bits = bits + 6
    if bits >= 8 then
      bits = bits - 8
      local byte = math.floor(buf / (2 ^ bits)) % 256
      out[#out + 1] = string.char(byte)
      buf = buf % (2 ^ bits)
    end
  end
  return table.concat(out)
end

---Decode a url-safe base64 string.
---@param input string
---@return string|nil decoded bytes, or nil if malformed
function M.decode(input)
  if type(input) ~= 'string' or #input == 0 then
    return nil
  end
  return decode_b64(to_standard(input))
end

return M
