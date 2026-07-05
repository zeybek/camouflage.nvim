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
    local function no_network_opts()
      return {
        pwned = { enabled = false },
        checks = {
          pwned = { enabled = false },
        },
      }
    end

    local function create_named_buffer(lines, filename)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, filename)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_set_current_buf(bufnr)
      return bufnr
    end

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

    it('should mask supported buffers loaded before setup', function()
      local bufnr = create_named_buffer({ 'API_KEY=secret' }, vim.fn.tempname() .. '.env')

      camouflage.setup(no_network_opts())

      local state = require('camouflage.state')
      local variables = state.get_variables(bufnr)
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})

      assert.is_true(state.is_buffer_masked(bufnr))
      assert.equals(1, #variables)
      assert.equals('API_KEY', variables[1].key)
      assert.equals('secret', variables[1].value)
      assert.equals(1, #extmarks)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should run check hooks during the initial loaded-buffer pass', function()
      local bufnr = create_named_buffer({ 'PASSWORD=password' }, vim.fn.tempname() .. '.env')

      camouflage.setup(no_network_opts())

      local result = require('camouflage.checks.store').get(bufnr, 0, 'weak_secret')

      assert.is_table(result)
      assert.equals('[weak: default]', result.text)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should not decorate unsupported or project config buffers during setup', function()
      local unsupported =
        create_named_buffer({ 'API_KEY=secret' }, vim.fn.tempname() .. '.unsupported')
      local project_dir = vim.fn.tempname()
      vim.fn.mkdir(project_dir, 'p')
      local project_config =
        create_named_buffer({ 'API_KEY: secret' }, project_dir .. '/.camouflage.yaml')

      camouflage.setup(no_network_opts())

      local state = require('camouflage.state')
      for _, bufnr in ipairs({ unsupported, project_config }) do
        local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
        assert.is_false(state.is_buffer_masked(bufnr))
        assert.equals(0, #state.get_variables(bufnr))
        assert.equals(0, #extmarks)
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      vim.fn.delete(project_dir, 'rf')
    end)

    it('should not create runtime autocmds if parser setup fails', function()
      local state = require('camouflage.state')
      local original_preload = package.preload['camouflage.parsers.env']
      local original_loaded = package.loaded['camouflage.parsers.env']
      package.loaded['camouflage.parsers.env'] = nil
      package.preload['camouflage.parsers.env'] = function()
        error('parser setup boom')
      end

      local ok, err = pcall(function()
        camouflage.setup(no_network_opts())
      end)

      package.preload['camouflage.parsers.env'] = original_preload
      package.loaded['camouflage.parsers.env'] = original_loaded

      local found = tostring(err):find('parser setup boom', 1, true)
      local autocmds = vim.api.nvim_get_autocmds({ group = state.augroup })

      assert.is_false(ok)
      assert.is_not_nil(found)
      assert.equals(0, #autocmds)
    end)

    it('should not disable cmp for a supported buffer after masking stops', function()
      local original_cmp = package.loaded.cmp
      local disabled_calls = 0
      package.loaded.cmp = {
        setup = {
          buffer = function(opts)
            if opts and opts.enabled == false then
              disabled_calls = disabled_calls + 1
            end
          end,
        },
      }
      local bufnr = create_named_buffer({ 'API_KEY=secret' }, vim.fn.tempname() .. '.env')

      camouflage.setup(no_network_opts())

      local config = require('camouflage.config')
      local core = require('camouflage.core')
      local state = require('camouflage.state')
      assert.is_true(state.is_buffer_masked(bufnr))

      config.set('enabled', false)
      core.apply_decorations(bufnr)
      vim.api.nvim_exec_autocmds('BufEnter', { buffer = bufnr })

      package.loaded.cmp = original_cmp

      assert.is_false(state.is_buffer_masked(bufnr))
      assert.equals(0, disabled_calls)

      vim.api.nvim_buf_delete(bufnr, { force = true })
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
