local jwt = require('camouflage.checks.expiry.jwt')
local base64url = require('camouflage.checks.expiry.base64url')

-- Encode a Lua table as a JWT segment (url-safe base64 of JSON).
local function encode_segment(tbl)
  local json = vim.json.encode(tbl)
  local b64 = vim.base64.encode(json)
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
