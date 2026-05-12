---@mod camouflage.checks.expiry.jwt Minimal JWT parser
---@brief [[
--- Decodes a JWT into its header + payload claims. Only used for reading
--- the `exp` (expiry), `iss` (issuer), `sub`, and `iat` claims — no
--- signature verification is performed since we only need expiry hints.
---@brief ]]

local M = {}

local base64url = require('camouflage.checks.expiry.base64url')

---@class JWTHeader
---@field alg? string
---@field typ? string
---@field kid? string

---@class JWTClaims
---@field exp? integer Unix timestamp (seconds)
---@field iat? integer
---@field nbf? integer
---@field iss? string
---@field sub? string
---@field aud? string|string[]

---@class JWTToken
---@field header JWTHeader
---@field claims JWTClaims
---@field segments {header: string, payload: string, signature: string}

-- Conservative JWT shape regex: three dot-separated url-safe-base64 segments.
-- Allows quotes around the token (e.g. `"key": "eyJ..."`).
local SEGMENT_PAT = '[%w%-_]+'
local JWT_RE = '^' .. SEGMENT_PAT .. '%.' .. SEGMENT_PAT .. '%.' .. SEGMENT_PAT .. '$'

---Heuristic: a JWT-looking string starts with the standard JOSE header
---prefix (`eyJ`) which is base64url of `{"`.
---@param value string
---@return boolean
local function looks_like_jwt(value)
  if type(value) ~= 'string' or #value < 16 then
    return false
  end
  if not value:match(JWT_RE) then
    return false
  end
  -- Header must start with {"...
  return value:sub(1, 3) == 'eyJ'
end

---Try decoding a JSON segment.
---@param segment string base64url-encoded JSON
---@return table|nil
local function decode_segment(segment)
  local raw = base64url.decode(segment)
  if not raw then
    return nil
  end
  local ok, parsed = pcall(vim.json.decode, raw)
  if not ok or type(parsed) ~= 'table' then
    return nil
  end
  return parsed
end

---Decode a JWT string into its header and claims.
---Returns nil if the string is not a parsable JWT.
---@param value string
---@return JWTToken|nil
function M.decode(value)
  if not looks_like_jwt(value) then
    return nil
  end

  local header_seg, payload_seg, sig_seg =
    value:match('^(' .. SEGMENT_PAT .. ')%.(' .. SEGMENT_PAT .. ')%.(' .. SEGMENT_PAT .. ')$')
  if not header_seg or not payload_seg then
    return nil
  end

  local header = decode_segment(header_seg)
  if not header or not header.alg then
    -- A real JWT header always has `alg`; missing alg means random base64.
    return nil
  end

  local claims = decode_segment(payload_seg)
  if not claims then
    return nil
  end

  return {
    header = header,
    claims = claims,
    segments = {
      header = header_seg,
      payload = payload_seg,
      signature = sig_seg,
    },
  }
end

---Map a known `iss` claim value to a human-friendly provider name.
---@param iss string|nil
---@return string|nil
function M.provider_name(iss)
  if type(iss) ~= 'string' or #iss == 0 then
    return nil
  end
  local lower = iss:lower()
  if lower:find('accounts.google.com', 1, true) then
    return 'Google'
  elseif lower:find('.auth0.com', 1, true) then
    return 'Auth0'
  elseif lower:find('cognito-idp', 1, true) then
    return 'Cognito'
  elseif
    lower:find('login.microsoftonline.com', 1, true) or lower:find('sts.windows.net', 1, true)
  then
    return 'Microsoft'
  elseif lower:find('token.actions.githubusercontent.com', 1, true) then
    return 'GitHub Actions'
  elseif lower:find('github.com', 1, true) then
    return 'GitHub'
  elseif lower:find('okta.com', 1, true) then
    return 'Okta'
  elseif
    lower:find('firebaseapp.com', 1, true) or lower:find('securetoken.google.com', 1, true)
  then
    return 'Firebase'
  end
  return nil
end

return M
