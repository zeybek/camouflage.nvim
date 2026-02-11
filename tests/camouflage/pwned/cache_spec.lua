-- Pwned feature requires Neovim 0.10+ (vim.system)
if vim.fn.has('nvim-0.10') == 0 then
  describe('camouflage.pwned.cache (skipped)', function()
    it('requires Neovim 0.10+', function()
      pending('Pwned feature requires Neovim 0.10+')
    end)
  end)
  return
end

describe('camouflage.pwned.cache', function()
  local cache

  before_each(function()
    package.loaded['camouflage.pwned.cache'] = nil
    cache = require('camouflage.pwned.cache')
    cache.clear()
  end)

  describe('get', function()
    it('should return nil for non-existent key', function()
      local result = cache.get('nonexistent')
      assert.is_nil(result)
    end)
  end)

  describe('set', function()
    it('should store and retrieve a value', function()
      cache.set('ABC123', { pwned = true, count = 1000 })
      local result = cache.get('ABC123')
      assert.is_not_nil(result)
      assert.is_true(result.pwned)
      assert.equals(1000, result.count)
    end)

    it('should overwrite existing value', function()
      cache.set('ABC123', { pwned = true, count = 100 })
      cache.set('ABC123', { pwned = false, count = 0 })
      local result = cache.get('ABC123')
      assert.is_false(result.pwned)
      assert.equals(0, result.count)
    end)
  end)

  describe('clear', function()
    it('should remove all entries', function()
      cache.set('KEY1', { pwned = true, count = 1 })
      cache.set('KEY2', { pwned = false, count = 0 })
      cache.clear()
      assert.is_nil(cache.get('KEY1'))
      assert.is_nil(cache.get('KEY2'))
    end)
  end)

  describe('size', function()
    it('should return 0 for empty cache', function()
      assert.equals(0, cache.size())
    end)

    it('should return correct count', function()
      cache.set('KEY1', { pwned = true, count = 1 })
      cache.set('KEY2', { pwned = false, count = 0 })
      assert.equals(2, cache.size())
    end)
  end)
end)
