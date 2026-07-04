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

  local function with_system_unavailable(fn)
    local original_system = vim.system
    vim.system = nil
    local ok, err = pcall(fn)
    vim.system = original_system
    if not ok then
      error(err, 0)
    end
  end

  before_each(function()
    api = require('camouflage.pwned.api')
  end)

  describe('is_available', function()
    it('should return true when curl is available', function()
      -- curl should be available on most systems
      assert.is_true(api.is_available())
    end)

    it('returns false when vim.system is unavailable', function()
      with_system_unavailable(function()
        assert.is_false(api.is_available())
      end)
    end)
  end)

  describe('check_prefix', function()
    it('reports unavailable instead of throwing when vim.system is absent', function()
      with_system_unavailable(function()
        local done = false
        local err
        local suffixes = 'unset'
        assert.has_no.errors(function()
          api.check_prefix('ABCDE', function(e, s)
            err = e
            suffixes = s
            done = true
          end)
        end)

        vim.wait(500, function()
          return done
        end)

        assert.is_true(done)
        assert.matches('unavailable', err)
        assert.is_nil(suffixes)
      end)
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
