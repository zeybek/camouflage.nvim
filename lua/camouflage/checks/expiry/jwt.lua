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

---Extract the bare host from an `iss` claim, which may be a full URL or a bare
---host (Google legacy tokens use `accounts.google.com` with no scheme).
---@param iss string
---@return string
local function iss_host(iss)
  local s = iss:lower()
  s = s:gsub('^%a[%w+.%-]*://', '') -- strip scheme
  s = s:gsub('[/?#].*$', '') -- cut path/query/fragment
  s = s:gsub('^[^@]*@', '') -- strip userinfo
  s = s:gsub(':%d+$', '') -- strip port
  return s
end

---Whether host equals domain or is a subdomain of it (dot-suffix).
---@param host string
---@param domain string
---@return boolean
local function host_matches(host, domain)
  return host == domain or host:sub(-(#domain + 1)) == '.' .. domain
end

-- Ordered provider matchers. Anchored host comparison (exact or dot-suffix)
-- instead of substring find, so a hostile issuer like
-- `https://github.com.evil.example` is not mislabelled as GitHub.
local PROVIDERS = {
  { name = 'Google', domain = 'accounts.google.com' },
  { name = 'Firebase', domain = 'securetoken.google.com' },
  { name = 'Firebase', domain = 'firebaseapp.com' },
  { name = 'Auth0', domain = 'auth0.com' },
  { name = 'Microsoft', domain = 'login.microsoftonline.com' },
  { name = 'Microsoft', domain = 'sts.windows.net' },
  { name = 'GitHub Actions', domain = 'token.actions.githubusercontent.com' },
  { name = 'GitHub', domain = 'github.com' },
  { name = 'Okta', domain = 'okta.com' },
  {
    name = 'Cognito',
    fn = function(host)
      return host:match('^cognito%-idp%.') ~= nil and host_matches(host, 'amazonaws.com')
    end,
  },
}

---Map a known `iss` claim value to a human-friendly provider name.
---@param iss string|nil
---@return string|nil
function M.provider_name(iss)
  if type(iss) ~= 'string' or #iss == 0 then
    return nil
  end
  local host = iss_host(iss)
  if host == '' then
    return nil
  end
  for _, p in ipairs(PROVIDERS) do
    if p.fn then
      if p.fn(host) then
        return p.name
      end
    elseif host_matches(host, p.domain) then
      return p.name
    end
  end
  return nil
end

return M
