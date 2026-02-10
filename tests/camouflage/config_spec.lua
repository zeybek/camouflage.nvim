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
  end)

  describe('get_style', function()
    it('should return current style', function()
      config.setup({ style = 'scramble' })
      assert.equals('scramble', config.get_style())
    end)
  end)
end)
