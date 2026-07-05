describe('camouflage.commands', function()
  local function clear_camouflage_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function create_env_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '.env')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  before_each(function()
    clear_camouflage_modules()
    require('camouflage').setup({
      pwned = { enabled = false },
      checks = {
        pwned = { enabled = false },
      },
    })
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

  it('should create CamouflageAudit command', function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands['CamouflageAudit'])
  end)

  it('should create CamouflageWeakSecretToggle command', function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands['CamouflageWeakSecretToggle'])
  end)

  it('should create CamouflageYank command', function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands['CamouflageYank'])
  end)

  it('should create CamouflageReveal command', function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands['CamouflageReveal'])
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

  describe('CamouflageWeakSecretToggle', function()
    it('should toggle enabled state and clear weak-secret badges when disabled', function()
      local config = require('camouflage.config')
      local checks = require('camouflage.checks')
      local store = require('camouflage.checks.store')
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'PASSWORD=password' })
      checks.set_result(bufnr, 0, 'weak_secret', { severity = 'warning', text = '[weak: default]' })

      local original_notify = vim.notify
      vim.notify = function() end

      vim.cmd('CamouflageWeakSecretToggle')

      vim.notify = original_notify

      assert.is_false(config.get_check('weak_secret').enabled)
      assert.is_nil(store.get(bufnr, 0, 'weak_secret'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
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

    it('should include policy state and ignored count without plaintext values', function()
      local state = require('camouflage.state')
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '.env')
      vim.api.nvim_set_current_buf(bufnr)
      state.update_buffer(bufnr, {
        enabled = true,
        variables = {
          { key = 'API_KEY', value = 'status-secret-should-not-return' },
        },
        parser = 'env',
        policy_stats = {
          ignored = 2,
        },
      })

      local message
      local original_notify = vim.notify
      vim.notify = function(msg)
        message = msg
      end

      vim.cmd('CamouflageStatus')

      vim.notify = original_notify

      assert.is_string(message)
      assert.is_not_nil(message:find('Policy: enabled', 1, true))
      assert.is_not_nil(message:find('Policy ignored: 2', 1, true))
      assert.is_nil(message:find('status-secret-should-not-return', 1, true))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should report unmasked state after global disable clears stale variables', function()
      local camouflage = require('camouflage')
      local core = require('camouflage.core')
      local bufnr = create_env_buffer({ 'API_KEY=status-stale-secret' })

      core.apply_decorations(bufnr)
      camouflage.disable()

      local message
      local original_notify = vim.notify
      vim.notify = function(msg)
        message = msg
      end

      vim.cmd('CamouflageStatus')

      vim.notify = original_notify

      assert.is_string(message)
      assert.is_not_nil(message:find('Global: disabled', 1, true))
      assert.is_not_nil(message:find('Buffer: not masked', 1, true))
      assert.is_not_nil(message:find('Masked values: 0', 1, true))
      assert.is_nil(message:find('status-stale-secret', 1, true))
      vim.api.nvim_buf_delete(bufnr, { force = true })
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

    it('should not copy stale values after global disable', function()
      local camouflage = require('camouflage')
      local core = require('camouflage.core')
      local bufnr = create_env_buffer({ 'API_KEY=yank-stale-secret' })
      vim.api.nvim_win_set_cursor(0, { 1, 10 })
      core.apply_decorations(bufnr)
      vim.fn.setreg('a', 'original')

      local original_notify = vim.notify
      vim.notify = function() end

      camouflage.disable()
      vim.cmd('CamouflageYank a')

      vim.notify = original_notify

      assert.equals('original', vim.fn.getreg('a'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('CamouflageReveal', function()
    it('should not error when executed on buffer without variables', function()
      local original_notify = vim.notify
      vim.notify = function() end

      assert.has_no.errors(function()
        vim.cmd('CamouflageReveal')
      end)

      vim.notify = original_notify
    end)
  end)
end)
