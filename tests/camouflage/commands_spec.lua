describe('camouflage.commands', function()
  local function clear_camouflage_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  before_each(function()
    clear_camouflage_modules()
    require('camouflage').setup()
  end)

  it('should create CamouflageToggle command', function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands['CamouflageToggle'])
  end)

  it('should create CamouflageRefresh command', function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands['CamouflageRefresh'])
  end)

  it('should create CamouflageStatus command', function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands['CamouflageStatus'])
  end)

  it('should create CamouflageYank command', function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands['CamouflageYank'])
  end)

  describe('CamouflageToggle', function()
    it('should toggle enabled state', function()
      local camouflage = require('camouflage')
      local initial = camouflage.is_enabled()

      -- Suppress notification output
      local original_notify = vim.notify
      vim.notify = function() end

      vim.cmd('CamouflageToggle')

      vim.notify = original_notify

      assert.equals(not initial, camouflage.is_enabled())
    end)
  end)

  describe('CamouflageRefresh', function()
    it('should not error when executed', function()
      -- Suppress notification output
      local original_notify = vim.notify
      vim.notify = function() end

      assert.has_no.errors(function()
        vim.cmd('CamouflageRefresh')
      end)

      vim.notify = original_notify
    end)
  end)

  describe('CamouflageStatus', function()
    it('should not error when executed', function()
      -- Suppress notification output
      local original_notify = vim.notify
      vim.notify = function() end

      assert.has_no.errors(function()
        vim.cmd('CamouflageStatus')
      end)

      vim.notify = original_notify
    end)
  end)

  describe('CamouflageYank', function()
    it('should not error when executed on buffer without variables', function()
      local original_notify = vim.notify
      vim.notify = function() end

      assert.has_no.errors(function()
        vim.cmd('CamouflageYank')
      end)

      vim.notify = original_notify
    end)
  end)
end)
