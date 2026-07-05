describe('camouflage.autocmds', function()
  local autocmds
  local state

  local function clear_camouflage_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function pwned_autocmds(event)
    local query = { group = state.augroup }
    if event then
      query.event = event
    end
    local results = {}
    for _, au in ipairs(vim.api.nvim_get_autocmds(query)) do
      if au.desc and au.desc:find('Camouflage pwned', 1, true) then
        table.insert(results, au)
      end
    end
    return results
  end

  before_each(function()
    clear_camouflage_modules()
    require('camouflage.config').setup()
    state = require('camouflage.state')
    autocmds = require('camouflage.autocmds')
  end)

  describe('setup', function()
    it('should create autocmds for BufEnter', function()
      autocmds.setup()

      local aus = vim.api.nvim_get_autocmds({
        group = state.augroup,
        event = 'BufEnter',
      })

      assert.is_true(#aus > 0)
    end)

    it('should create autocmds for TextChanged', function()
      autocmds.setup()

      local aus = vim.api.nvim_get_autocmds({
        group = state.augroup,
        event = 'TextChanged',
      })

      assert.is_true(#aus > 0)
    end)

    it('should create autocmds for TextChangedI', function()
      autocmds.setup()

      local aus = vim.api.nvim_get_autocmds({
        group = state.augroup,
        event = 'TextChangedI',
      })

      assert.is_true(#aus > 0)
    end)

    it('should create autocmds for BufDelete', function()
      autocmds.setup()

      local aus = vim.api.nvim_get_autocmds({
        group = state.augroup,
        event = 'BufDelete',
      })

      assert.is_true(#aus > 0)
    end)

    it('should create autocmds for User CamouflageConfigChanged', function()
      autocmds.setup()

      local aus = vim.api.nvim_get_autocmds({
        group = state.augroup,
        event = 'User',
        pattern = 'CamouflageConfigChanged',
      })

      assert.is_true(#aus > 0)
    end)

    it('should not create HIBP network-check autocmds by default', function()
      autocmds.setup()

      assert.equals(0, #pwned_autocmds())
    end)

    it('should only create the opted-in HIBP BufEnter autocmd', function()
      require('camouflage.config').setup({
        pwned = {
          auto_check = true,
        },
      })

      autocmds.setup()

      assert.is_true(#pwned_autocmds('BufEnter') > 0)
      assert.equals(0, #pwned_autocmds('BufWritePost'))
      assert.equals(0, #pwned_autocmds('TextChanged'))
      assert.equals(0, #pwned_autocmds('TextChangedI'))
    end)

    it('should only create the opted-in HIBP BufWritePost autocmd', function()
      require('camouflage.config').setup({
        pwned = {
          check_on_save = true,
        },
      })

      autocmds.setup()

      assert.equals(0, #pwned_autocmds('BufEnter'))
      assert.is_true(#pwned_autocmds('BufWritePost') > 0)
      assert.equals(0, #pwned_autocmds('TextChanged'))
      assert.equals(0, #pwned_autocmds('TextChangedI'))
    end)

    it('should only create the opted-in HIBP text-change autocmds', function()
      require('camouflage.config').setup({
        pwned = {
          check_on_change = true,
        },
      })

      autocmds.setup()

      assert.equals(0, #pwned_autocmds('BufEnter'))
      assert.equals(0, #pwned_autocmds('BufWritePost'))
      assert.is_true(#pwned_autocmds('TextChanged') > 0)
      assert.is_true(#pwned_autocmds('TextChangedI') > 0)
    end)
  end)

  describe('disable', function()
    it('should clear all autocmds', function()
      autocmds.setup()

      -- Verify autocmds exist
      local aus_before = vim.api.nvim_get_autocmds({
        group = state.augroup,
      })
      assert.is_true(#aus_before > 0)

      autocmds.disable()

      local aus_after = vim.api.nvim_get_autocmds({
        group = state.augroup,
      })
      assert.equals(0, #aus_after)
    end)
  end)

  describe('apply_to_loaded_buffers', function()
    it('should not error when called', function()
      autocmds.setup()

      assert.has_no.errors(function()
        autocmds.apply_to_loaded_buffers()
      end)
    end)
  end)
end)
