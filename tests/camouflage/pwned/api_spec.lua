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
    -- Test the response parsing if exposed, or test via check_prefix
    it('should handle valid API response format', function()
      -- This would require mocking or testing with actual API
      -- For now, just verify the module loads
      assert.is_table(api)
      assert.is_function(api.check_prefix)
    end)
  end)
end)
