-- Pwned feature requires Neovim 0.10+ (vim.system)
if vim.fn.has('nvim-0.10') == 0 then
  describe('camouflage.pwned.api (skipped)', function()
    it('requires Neovim 0.10+', function()
      pending('Pwned feature requires Neovim 0.10+')
    end)
  end)
  return
end

describe('camouflage.pwned.api', function()
  local api

  before_each(function()
    api = require('camouflage.pwned.api')
  end)

  describe('is_available', function()
    it('should return true when curl is available', function()
      -- curl should be available on most systems
      assert.is_true(api.is_available())
    end)
  end)

  describe('parse_response', function()
    it('should parse SUFFIX:COUNT lines into an uppercase map', function()
      local body = '0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n00D4F6E8FA6EECAD2A3AA415EEC418D38EC:2'
      local suffixes = api.parse_response(body)
      assert.equals(1, suffixes['0018A45C4D1DEF81644B54AB7F969B88D65'])
      assert.equals(2, suffixes['00D4F6E8FA6EECAD2A3AA415EEC418D38EC'])
    end)

    it('should drop zero-count padding entries', function()
      -- Padding entries (Add-Padding) always arrive with count 0 and must be
      -- discarded so a consumer never reports a false breach.
      local body = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:0\nBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB:5'
      local suffixes = api.parse_response(body)
      assert.is_nil(suffixes['AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'])
      assert.equals(5, suffixes['BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'])
    end)
  end)
end)
