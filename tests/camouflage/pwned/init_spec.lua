describe('camouflage.pwned', function()
  local pwned

  before_each(function()
    pwned = require('camouflage.pwned')
  end)

  describe('setup', function()
    it('should not error', function()
      assert.has_no.errors(function()
        pwned.setup()
      end)
    end)
  end)

  describe('is_available', function()
    it('should return boolean', function()
      local result = pwned.is_available()
      assert.is_boolean(result)
    end)

    it('should return true when dependencies are met', function()
      -- On most systems with curl and sha1sum
      assert.is_true(pwned.is_available())
    end)
  end)

  describe('clear', function()
    it('should not error on empty buffer', function()
      assert.has_no.errors(function()
        pwned.clear()
      end)
    end)
  end)

  describe('clear_cache', function()
    it('should clear the cache', function()
      local cache = require('camouflage.pwned.cache')
      cache.set('TEST', { pwned = true, count = 1 })
      pwned.clear_cache()
      assert.is_nil(cache.get('TEST'))
    end)
  end)

  describe('API exposure', function()
    it('should expose check_current function', function()
      assert.is_function(pwned.check_current)
    end)

    it('should expose check_line function', function()
      assert.is_function(pwned.check_line)
    end)

    it('should expose check_buffer function', function()
      assert.is_function(pwned.check_buffer)
    end)
  end)
end)
