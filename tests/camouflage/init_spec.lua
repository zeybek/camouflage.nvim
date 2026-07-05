describe('camouflage.init', function()
  local camouflage

  -- Helper to clear all camouflage modules from package.loaded
  local function clear_camouflage_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  before_each(function()
    clear_camouflage_modules()
    camouflage = require('camouflage')
  end)

  describe('setup', function()
    it('should initialize without options', function()
      assert.has_no.errors(function()
        camouflage.setup()
      end)
    end)

    it('should merge user options', function()
      camouflage.setup({
        style = 'dotted',
        enabled = false,
      })

      local config = require('camouflage.config')
      assert.equals('dotted', config.get().style)
      assert.is_false(config.get().enabled)
    end)

    it('should warn when called twice', function()
      local notified = false
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match('Already initialized') and level == vim.log.levels.WARN then
          notified = true
        end
      end

      camouflage.setup()
      camouflage.setup()

      vim.notify = original_notify
      assert.is_true(notified)
    end)
  end)

  describe('enable/disable', function()
    before_each(function()
      clear_camouflage_modules()
      camouflage = require('camouflage')
      camouflage.setup({ enabled = false })
    end)

    it('should enable masking', function()
      assert.is_false(camouflage.is_enabled())

      camouflage.enable()

      assert.is_true(camouflage.is_enabled())
    end)

    it('should disable masking', function()
      camouflage.enable()
      assert.is_true(camouflage.is_enabled())

      camouflage.disable()

      assert.is_false(camouflage.is_enabled())
    end)

    it('should toggle masking', function()
      assert.is_false(camouflage.is_enabled())

      camouflage.toggle()
      assert.is_true(camouflage.is_enabled())

      camouflage.toggle()
      assert.is_false(camouflage.is_enabled())
    end)
  end)

  describe('is_enabled', function()
    before_each(function()
      clear_camouflage_modules()
      camouflage = require('camouflage')
    end)

    it('should return true when enabled', function()
      camouflage.setup({ enabled = true })

      assert.is_true(camouflage.is_enabled())
    end)

    it('should return false when disabled', function()
      camouflage.setup({ enabled = false })

      assert.is_false(camouflage.is_enabled())
    end)
  end)

  describe('version', function()
    it('should have version field', function()
      assert.is_string(camouflage.version)
    end)

    it('should have valid semver format', function()
      assert.is_truthy(camouflage.version:match('^%d+%.%d+%.%d+'))
    end)
  end)

  describe('refresh', function()
    before_each(function()
      clear_camouflage_modules()
      camouflage = require('camouflage')
      camouflage.setup()
    end)

    it('should not error when called', function()
      assert.has_no.errors(function()
        camouflage.refresh()
      end)
    end)
  end)

  describe('check API', function()
    before_each(function()
      clear_camouflage_modules()
      camouflage = require('camouflage')
    end)

    it('should expose register, unregister, list, and get functions', function()
      assert.is_function(camouflage.register_check)
      assert.is_function(camouflage.unregister_check)
      assert.is_function(camouflage.list_checks)
      assert.is_function(camouflage.get_check)
    end)

    it('should register checks through the public API', function()
      local entry = camouflage.register_check({
        name = 'api_check',
        run = function() end,
      })

      assert.equals('api_check', entry.name)
      assert.equals('api_check', camouflage.get_check('api_check').name)
      assert.equals(1, #camouflage.list_checks())
      assert.is_true(camouflage.unregister_check('api_check'))
      assert.is_nil(camouflage.get_check('api_check'))
    end)
  end)
end)
