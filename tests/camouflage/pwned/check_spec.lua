-- Pwned feature requires Neovim 0.10+ (vim.system)
if vim.fn.has('nvim-0.10') == 0 then
  describe('camouflage.pwned.check (skipped)', function()
    it('requires Neovim 0.10+', function()
      pending('Pwned feature requires Neovim 0.10+')
    end)
  end)
  return
end

describe('camouflage.pwned.check', function()
  local check
  local saved = {}

  -- check.lua binds hash/api/ui at require() time, so stub via package.loaded
  -- and force a reload. The real cache module (pure in-memory) is used as-is.
  local function stub(name, tbl)
    saved[name] = package.loaded[name]
    package.loaded[name] = tbl
  end

  local FAKE_HASH = string.rep('A', 40)

  before_each(function()
    stub('camouflage.pwned.hash', {
      sha1 = function(_, cb)
        cb({ hash = FAKE_HASH, prefix = FAKE_HASH:sub(1, 5), suffix = FAKE_HASH:sub(6) })
      end,
    })
    stub('camouflage.pwned.api', {
      _suffixes = {},
      check_prefix = function(_, cb)
        cb(nil, package.loaded['camouflage.pwned.api']._suffixes)
      end,
    })
    stub('camouflage.pwned.ui', { mark_pwned = function() end })

    package.loaded['camouflage.pwned.check'] = nil
    check = require('camouflage.pwned.check')
    require('camouflage.pwned.cache').clear()
  end)

  after_each(function()
    for name, mod in pairs(saved) do
      package.loaded[name] = mod
    end
    saved = {}
    package.loaded['camouflage.pwned.check'] = nil
  end)

  it('reports pwned with the breach count when the suffix is present', function()
    package.loaded['camouflage.pwned.api']._suffixes = { [FAKE_HASH:sub(6)] = 42 }

    local result
    check.check_value('secret', function(r)
      result = r
    end)

    assert.is_table(result)
    assert.is_true(result.pwned)
    assert.equals(42, result.count)
  end)

  it('reports not pwned when the suffix is absent', function()
    package.loaded['camouflage.pwned.api']._suffixes = {}

    local result = 'unset'
    check.check_value('secret', function(r)
      result = r
    end)

    assert.is_table(result)
    assert.is_false(result.pwned)
    assert.equals(0, result.count)
  end)

  it('returns nil on an API error and does not cache the failure', function()
    package.loaded['camouflage.pwned.api'].check_prefix = function(_, cb)
      cb('network down', nil)
    end

    local called, result = false, 'unset'
    check.check_value('secret', function(r)
      called = true
      result = r
    end)

    assert.is_true(called)
    assert.is_nil(result)
    -- Nothing cached, so a subsequent successful call still hits the API.
    assert.is_nil(require('camouflage.pwned.cache').get(FAKE_HASH))
  end)
end)
