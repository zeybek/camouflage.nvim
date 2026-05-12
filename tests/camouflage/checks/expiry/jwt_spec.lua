local jwt = require('camouflage.checks.expiry.jwt')
local base64url = require('camouflage.checks.expiry.base64url')

-- Pure-Lua base64 encoder (vim.base64.encode is Neovim 0.10+).
local ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64_encode(input)
  local out, i = {}, 1
  while i <= #input do
    local b1 = string.byte(input, i) or 0
    local b2 = string.byte(input, i + 1)
    local b3 = string.byte(input, i + 2)
    local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
    table.insert(out, ALPHA:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1))
    table.insert(out, ALPHA:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1))
    table.insert(
      out,
      b2 and ALPHA:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or '='
    )
    table.insert(out, b3 and ALPHA:sub(n % 64 + 1, n % 64 + 1) or '=')
    i = i + 3
  end
  return table.concat(out)
end

-- Encode a Lua table as a JWT segment (url-safe base64 of JSON).
local function encode_segment(tbl)
  local json = vim.json.encode(tbl)
  local b64 = b64_encode(json)
  return (b64:gsub('+', '-'):gsub('/', '_'):gsub('=', ''))
end

local function make_jwt(header, claims, sig)
  return table.concat({
    encode_segment(header or { alg = 'HS256', typ = 'JWT' }),
    encode_segment(claims or {}),
    sig or 'fakesignature',
  }, '.')
end

describe('camouflage.checks.expiry.base64url', function()
  it('decodes url-safe base64 with stripped padding', function()
    -- 'hello' -> 'aGVsbG8=' standard, 'aGVsbG8' url-safe stripped
    assert.equals('hello', base64url.decode('aGVsbG8'))
  end)

  it('handles +/= replacement (url-safe chars)', function()
    -- '?' -> 'Pw==' standard, 'Pw' url-safe stripped
    assert.equals('?', base64url.decode('Pw'))
  end)

  it('returns nil for malformed input', function()
    assert.is_nil(base64url.decode('!!!!'))
  end)

  it('returns nil for empty input', function()
    assert.is_nil(base64url.decode(''))
  end)
end)

describe('camouflage.checks.expiry.jwt', function()
  it('decodes a well-formed JWT', function()
    local token = make_jwt(
      { alg = 'RS256', typ = 'JWT' },
      { exp = 9999999999, iss = 'https://accounts.google.com' }
    )
    local decoded = jwt.decode(token)
    assert.is_table(decoded)
    assert.equals('RS256', decoded.header.alg)
    assert.equals(9999999999, decoded.claims.exp)
    assert.equals('https://accounts.google.com', decoded.claims.iss)
  end)

  it('returns nil for non-JWT strings', function()
    assert.is_nil(jwt.decode('not a token'))
    assert.is_nil(jwt.decode('one.two'))
    assert.is_nil(jwt.decode(''))
    assert.is_nil(jwt.decode('aaaaaaaaaaaaaaa.bbbbbb.ccccc')) -- does not start with eyJ
  end)

  it('returns nil if header has no alg claim', function()
    local bad = make_jwt({ typ = 'JWT' }, { exp = 9999999999 }) -- no alg
    assert.is_nil(jwt.decode(bad))
  end)

  it('returns nil for malformed segments', function()
    assert.is_nil(jwt.decode('eyJBAD.eyJBAD.x'))
  end)

  it('decodes a JWT without exp claim (returns token, exp is nil)', function()
    local token = make_jwt(nil, { sub = 'user123' })
    local decoded = jwt.decode(token)
    assert.is_table(decoded)
    assert.is_nil(decoded.claims.exp)
  end)
end)

describe('camouflage.checks.expiry.jwt provider_name', function()
  it('detects Google', function()
    assert.equals('Google', jwt.provider_name('https://accounts.google.com'))
  end)

  it('detects Auth0', function()
    assert.equals('Auth0', jwt.provider_name('https://example.auth0.com/'))
  end)

  it('detects Cognito', function()
    assert.equals('Cognito', jwt.provider_name('https://cognito-idp.us-east-1.amazonaws.com/foo'))
  end)

  it('detects GitHub Actions', function()
    assert.equals(
      'GitHub Actions',
      jwt.provider_name('https://token.actions.githubusercontent.com')
    )
  end)

  it('returns nil for unknown issuers', function()
    assert.is_nil(jwt.provider_name('https://unknown.example.com'))
  end)

  it('returns nil for empty/nil input', function()
    assert.is_nil(jwt.provider_name(nil))
    assert.is_nil(jwt.provider_name(''))
  end)
end)
