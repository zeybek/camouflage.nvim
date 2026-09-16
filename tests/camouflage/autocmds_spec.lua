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

  describe('TextChanged', function()
    local buffers = {}

    local function setup_masking(opts)
      require('camouflage.config').setup(vim.tbl_deep_extend('force', {
        debounce_ms = 0,
        project_config = { enabled = false },
      }, opts or {}))
      require('camouflage.parsers').setup()
      autocmds.setup()
    end

    -- Entering the buffer runs the BufEnter autocmd, like opening a file.
    local function enter_buffer(name, lines)
      local bufnr = vim.api.nvim_create_buf(true, false)
      table.insert(buffers, bufnr)
      vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '/' .. name)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_set_current_buf(bufnr)
      return bufnr
    end

    local function type_lines(bufnr, lines)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd('doautocmd TextChanged')
      end)
    end

    local function mark_count(bufnr)
      return #vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
    end

    local function wait_for_marks(bufnr)
      return vim.wait(1000, function()
        return mark_count(bufnr) > 0
      end, 10)
    end

    after_each(function()
      for _, bufnr in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      buffers = {}
    end)

    it('masks a value typed into a buffer that had no values', function()
      setup_masking()
      local bufnr = enter_buffer('empty.env', {})
      assert.is_false(state.is_buffer_masked(bufnr))

      type_lines(bufnr, { 'API_KEY=typedsecret123' })

      assert.is_true(wait_for_marks(bufnr), 'typed value was not masked')
      assert.is_true(state.is_buffer_masked(bufnr))
    end)

    it('masks a value typed into a buffer that only has comments', function()
      setup_masking({ debounce_ms = 20 })
      local bufnr = enter_buffer('comments.env', { '# no values yet' })
      assert.is_false(state.is_buffer_masked(bufnr))

      type_lines(bufnr, { '# no values yet', 'TOKEN=commentfilesecret' })

      assert.is_true(wait_for_marks(bufnr), 'typed value was not masked')
    end)

    it('masks a new value after every existing value was deleted', function()
      setup_masking()
      local bufnr = enter_buffer('cleared.env', { 'OLD=existingvalue1' })
      assert.equals(1, mark_count(bufnr))

      type_lines(bufnr, { '' })
      assert.is_true(vim.wait(1000, function()
        return not state.is_buffer_masked(bufnr)
      end, 10))
      assert.equals(0, mark_count(bufnr))

      type_lines(bufnr, { 'NEW=afterclearsecret' })

      assert.is_true(wait_for_marks(bufnr), 'value typed after clearing was not masked')
    end)

    it('does not start masking buffers that were never tracked', function()
      setup_masking({ auto_enable = false })
      local bufnr = enter_buffer('manual.env', {})
      assert.is_nil(state.get_buffer(bufnr))

      type_lines(bufnr, { 'API_KEY=manualmodevalue' })
      vim.wait(100)

      assert.is_nil(state.get_buffer(bufnr))
      assert.equals(0, mark_count(bufnr))
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
