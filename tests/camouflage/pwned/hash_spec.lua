-- Pwned feature requires Neovim 0.10+ (vim.system)
if vim.fn.has('nvim-0.10') == 0 then
  describe('camouflage.pwned.hash (skipped)', function()
    it('requires Neovim 0.10+', function()
      pending('Pwned feature requires Neovim 0.10+')
    end)
  end)
  return
end

describe('camouflage.pwned.hash', function()
  local hash

  before_each(function()
    hash = require('camouflage.pwned.hash')
  end)

  describe('is_available', function()
    it('should return true when sha1sum or openssl is available', function()
      -- Most systems have at least one
      assert.is_true(hash.is_available())
    end)
  end)

  describe('has_sha1sum', function()
    it('should return boolean', function()
      local result = hash.has_sha1sum()
      assert.is_boolean(result)
    end)
  end)

  describe('has_openssl', function()
    it('should return boolean', function()
      local result = hash.has_openssl()
      assert.is_boolean(result)
    end)
  end)

  describe('sha1', function()
    it('should hash a known value correctly', function()
      -- "password" should hash to 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
      local done = false
      local result = nil

      hash.sha1('password', function(r)
        result = r
        done = true
      end)

      vim.wait(5000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals('5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8', result.hash)
      assert.equals('5BAA6', result.prefix)
      assert.equals('1E4C9B93F3F0682250B6CF8331B7EE68FD8', result.suffix)
    end)

    it('should return uppercase hash', function()
      local done = false
      local result = nil

      hash.sha1('test', function(r)
        result = r
        done = true
      end)

      vim.wait(5000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(result.hash, result.hash:upper())
    end)

    it('should handle empty string', function()
      local done = false
      local result = nil

      hash.sha1('', function(r)
        result = r
        done = true
      end)

      vim.wait(5000, function()
        return done
      end)

      -- Empty string has a valid SHA-1 hash
      assert.is_not_nil(result)
      assert.equals(40, #result.hash)
    end)

    it('should handle special characters', function()
      local done = false
      local result = nil

      hash.sha1('p@$$w0rd!#$%', function(r)
        result = r
        done = true
      end)

      vim.wait(5000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(40, #result.hash)
      assert.equals(5, #result.prefix)
      assert.equals(35, #result.suffix)
    end)
  end)
end)
