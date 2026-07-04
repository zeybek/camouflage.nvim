local config = require('camouflage.config')

describe('camouflage.config', function()
  before_each(function()
    -- Reset config before each test
    config.options = {}
  end)

  describe('setup', function()
    it('should use defaults when no opts provided', function()
      config.setup()
      assert.equals(true, config.get().enabled)
      assert.equals('stars', config.get().style)
    end)

    it('should merge user options with defaults', function()
      config.setup({
        style = 'dotted',
      })
      assert.equals('dotted', config.get().style)
      -- Default should still be there
      assert.equals('*', config.get().mask_char)
    end)

    it('should have default debounce_ms of 150', function()
      config.setup()
      assert.equals(150, config.get().debounce_ms)
    end)

    it('should allow custom debounce_ms', function()
      config.setup({ debounce_ms = 0 })
      assert.equals(0, config.get().debounce_ms)
    end)
  end)

  describe('is_enabled', function()
    it('should return true by default', function()
      config.setup()
      assert.is_true(config.is_enabled())
    end)

    it('should return false when disabled', function()
      config.setup({ enabled = false })
      assert.is_false(config.is_enabled())
    end)
  end)

  describe('set', function()
    it('should update simple options', function()
      config.setup()
      config.set('enabled', false)
      assert.is_false(config.get().enabled)
    end)

    it('should update nested options with dot notation', function()
      config.setup()
      config.set('integrations.telescope', false)
      assert.is_false(config.get().integrations.telescope)
    end)

    it('should call refresh_all when value changes (hot reload)', function()
      config.setup({ style = 'stars' })

      local core = require('camouflage.core')
      local refresh_called = false
      local original_refresh = core.refresh_all
      core.refresh_all = function()
        refresh_called = true
      end

      config.set('style', 'dotted')

      vim.wait(100, function()
        return refresh_called
      end)

      assert.is_true(refresh_called)
      core.refresh_all = original_refresh
    end)

    it('should NOT call refresh_all when value is same', function()
      config.setup({ style = 'stars' })

      local core = require('camouflage.core')
      local refresh_called = false
      local original_refresh = core.refresh_all
      core.refresh_all = function()
        refresh_called = true
      end

      config.set('style', 'stars') -- Same value

      vim.wait(50, function()
        return refresh_called
      end)

      assert.is_false(refresh_called)
      core.refresh_all = original_refresh
    end)
  end)

  describe('get_style', function()
    it('should return current style', function()
      config.setup({ style = 'scramble' })
      assert.equals('scramble', config.get_style())
    end)
  end)

  describe('get_check', function()
    it('returns the canonical checks table for a name', function()
      config.setup({ pwned = { enabled = true } })
      assert.is_table(config.get_check('pwned'))
      -- pwned and checks.pwned are the same table (no drift possible)
      assert.equals(config.get().pwned, config.get_check('pwned'))
    end)

    it('returns an empty table for an unknown check', function()
      config.setup()
      assert.same({}, config.get_check('does_not_exist'))
    end)

    it('includes weak-secret defaults', function()
      config.setup()
      local weak_secret = config.get_check('weak_secret')
      assert.is_true(weak_secret.enabled)
      assert.equals(12, weak_secret.min_sensitive_length)
      assert.equals('[weak: %s]', weak_secret.virtual_text_format)
      assert.is_table(weak_secret.sensitive_key_patterns)
    end)
  end)

  describe('checks.pwned canonical namespace', function()
    it('lets checks.pwned override the legacy pwned key', function()
      config.setup({ pwned = { enabled = true }, checks = { pwned = { enabled = false } } })
      assert.is_false(config.get().pwned.enabled)
      assert.is_false(config.get_check('pwned').enabled)
    end)

    it('aliases pwned and checks.pwned to the same table', function()
      config.setup({ pwned = { auto_check = false } })
      assert.equals(config.get().pwned, config.get().checks.pwned)
    end)
  end)

  describe('set feedback', function()
    it('returns false on a missing intermediate path segment', function()
      config.setup()
      assert.is_false(config.set('nonexistent.deep.key', 1))
    end)

    it('returns true when the key path is valid', function()
      config.setup()
      assert.is_true(config.set('style', 'stars'))
    end)
  end)
end)
