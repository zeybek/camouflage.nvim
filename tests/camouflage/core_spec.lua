local core = require('camouflage.core')
local state = require('camouflage.state')
local config = require('camouflage.config')
local hooks = require('camouflage.hooks')
local check_registry = require('camouflage.checks.registry')
local checks_store = require('camouflage.checks.store')

local function setup_buffer(lines, filename)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, filename or (vim.fn.tempname() .. '.env'))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

local function assert_unmasked_state(bufnr)
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
  assert.equals(0, #extmarks)
  assert.equals(0, #state.get_variables(bufnr))
  assert.is_false(state.is_buffer_masked(bufnr))
  assert.is_nil(state.get_policy_stats(bufnr))
end

local function setup_masked_buffer(lines, filename)
  local bufnr = setup_buffer(lines, filename)
  core.apply_decorations(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
  assert.is_true(state.is_buffer_masked(bufnr))
  assert.is_true(#state.get_variables(bufnr) > 0)
  assert.is_true(#extmarks > 0)

  return bufnr
end

describe('camouflage.core', function()
  before_each(function()
    config.setup()
    hooks.clear()
    hooks.setup(nil)
    require('camouflage.parsers').setup()
    check_registry._reset()
    checks_store._reset()
    vim.wait(20, function()
      return false
    end)
    state.clear()
  end)

  describe('index_to_position', function()
    it('should convert index 0 to row 0, col 0', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      local pos = core.index_to_position(0, 0, lines)

      assert.is_not_nil(pos)
      assert.equals(0, pos.row)
      assert.equals(0, pos.col)
    end)

    it('should convert index within first line', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      local pos = core.index_to_position(0, 8, lines)

      assert.is_not_nil(pos)
      assert.equals(0, pos.row)
      assert.equals(8, pos.col)
    end)

    it('should convert index at end of first line', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      local pos = core.index_to_position(0, 14, lines)

      assert.is_not_nil(pos)
      assert.equals(0, pos.row)
      assert.equals(14, pos.col)
    end)

    it('should convert index at start of second line', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      -- First line is 14 chars, newline at 14, second line starts at 15
      local pos = core.index_to_position(0, 15, lines)

      assert.is_not_nil(pos)
      assert.equals(1, pos.row)
      assert.equals(0, pos.col)
    end)

    it('should convert index within second line', function()
      local lines = { 'API_KEY=secret', 'OTHER=value' }
      -- Second line starts at index 15, so 15+6=21 points to 'value'
      local pos = core.index_to_position(0, 21, lines)

      assert.is_not_nil(pos)
      assert.equals(1, pos.row)
      assert.equals(6, pos.col)
    end)

    it('should handle empty lines array', function()
      local lines = {}
      local pos = core.index_to_position(0, 5, lines)

      assert.is_nil(pos)
    end)

    it('should handle single character lines', function()
      local lines = { 'a', 'b', 'c' }
      local pos = core.index_to_position(0, 2, lines)

      assert.is_not_nil(pos)
      assert.equals(1, pos.row)
      assert.equals(0, pos.col)
    end)

    it('should clamp to last position for out of bounds index', function()
      local lines = { 'short' }
      local pos = core.index_to_position(0, 100, lines)

      assert.is_not_nil(pos)
      assert.equals(0, pos.row)
      assert.equals(5, pos.col)
    end)
  end)

  describe('clear_decorations', function()
    it('should clear namespace without errors', function()
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Should not throw
      assert.has_no.errors(function()
        core.clear_decorations(bufnr)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should use current buffer when bufnr not provided', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      assert.has_no.errors(function()
        core.clear_decorations()
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('is_masked', function()
    it('should return false when buffer has no state', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      assert.is_false(core.is_masked())

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should return true when buffer is masked', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      state.init_buffer(bufnr)

      assert.is_true(core.is_masked())

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should return false when buffer state is disabled', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      state.init_buffer(bufnr)
      state.update_buffer(bufnr, { enabled = false })

      assert.is_false(core.is_masked())

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('apply_decorations', function()
    it('should clear stale mask state when disabled', function()
      local bufnr = setup_masked_buffer({ 'API_KEY=secret' })

      config.set('enabled', false)

      assert.has_no.errors(function()
        core.apply_decorations(bufnr)
      end)

      assert_unmasked_state(bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should clear stale mask state when files exceed max_lines', function()
      local bufnr = setup_masked_buffer({ 'API_KEY=secret' })

      -- Create a buffer with many lines
      local lines = {}
      for i = 1, 100 do
        table.insert(lines, 'LINE_' .. i .. '=value' .. i)
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Set max_lines to a low value
      config.set('max_lines', 10)

      assert.has_no.errors(function()
        core.apply_decorations(bufnr)
      end)

      assert_unmasked_state(bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should skip buffer without filename', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      -- Buffer has no name, should exit early
      assert.has_no.errors(function()
        core.apply_decorations(bufnr)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should skip unsupported file types', function()
      local bufnr = setup_masked_buffer({ 'API_KEY=secret' })

      assert.has_no.errors(function()
        core.apply_decorations(bufnr, 'test.unsupported')
      end)

      assert_unmasked_state(bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should clear stale mask state when parser returns no variables', function()
      local bufnr = setup_masked_buffer({ 'API_KEY=secret' })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'plain text without assignments' })

      core.apply_decorations(bufnr)

      assert_unmasked_state(bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should clear stale mask state when buffer-local config disables masking', function()
      local bufnr = setup_masked_buffer({ 'API_KEY=secret' })
      vim.b[bufnr].camouflage_enabled = false

      core.apply_decorations(bufnr)

      assert_unmasked_state(bufnr)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should clear stale variables so yank, reveal, and checks cannot use them', function()
      local bufnr = setup_masked_buffer({ 'PASSWORD=password' })
      vim.api.nvim_win_set_cursor(0, { 1, 10 })

      config.set('enabled', false)
      core.apply_decorations(bufnr)

      local yank = require('camouflage.yank')
      local reveal = require('camouflage.reveal')
      local weak_secret = require('camouflage.checks.weak_secret')

      assert.is_nil(yank.find_variable_at_cursor(bufnr))
      reveal.reveal_line()
      assert.is_false(reveal.is_revealed())
      weak_secret.check_buffer(bufnr)
      assert.is_nil(checks_store.get(bufnr, 0, 'weak_secret'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should apply policy before storing and decorating variables', function()
      config.setup({
        policy = {
          rules = {
            { id = 'ignore-debug', action = 'ignore', key = { '^DEBUG$' } },
          },
        },
      })
      local bufnr = setup_buffer({ 'DEBUG=true', 'API_KEY=secret' })

      core.apply_decorations(bufnr)

      local variables = state.get_variables(bufnr)
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
      local stats = state.get_policy_stats(bufnr)

      assert.equals(1, #variables)
      assert.equals('API_KEY', variables[1].key)
      assert.equals(1, #marks)
      assert.equals(2, stats.total)
      assert.equals(1, stats.ignored)
      assert.equals(1, stats.masked)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should let allow_force mask rules survive broad ignore rules', function()
      config.setup({
        policy = {
          rules = {
            { id = 'ignore-all', action = 'ignore', key = { '.+' } },
            {
              id = 'force-client-secret',
              action = 'mask',
              allow_force = true,
              key = { '^CLIENT_SECRET$' },
            },
          },
        },
      })
      local bufnr = setup_buffer({ 'CLIENT_SECRET=secret', 'DEBUG=true' })

      core.apply_decorations(bufnr)

      local variables = state.get_variables(bufnr)
      local stats = state.get_policy_stats(bufnr)

      assert.equals(1, #variables)
      assert.equals('CLIENT_SECRET', variables[1].key)
      assert.equals('force-client-secret', variables[1].policy.rule_id)
      assert.equals(1, stats.ignored)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should run variable_detected hooks after policy filtering', function()
      config.setup({
        policy = {
          rules = {
            { id = 'ignore-debug', action = 'ignore', key = { '^DEBUG$' } },
          },
        },
      })
      local seen = {}
      hooks.on('variable_detected', function(_, var)
        seen[var.key] = true
      end)
      local bufnr = setup_buffer({ 'DEBUG=true', 'API_KEY=secret' })

      core.apply_decorations(bufnr)

      assert.is_nil(seen.DEBUG)
      assert.is_true(seen.API_KEY)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should keep policy stats when every parsed variable is ignored', function()
      config.setup({
        policy = {
          rules = {
            { id = 'ignore-debug', action = 'ignore', key = { '^DEBUG$' } },
          },
        },
      })
      local bufnr = setup_buffer({ 'DEBUG=true' })

      core.apply_decorations(bufnr)

      local stats = state.get_policy_stats(bufnr)
      assert.is_false(state.is_buffer_masked(bufnr))
      assert.same({}, state.get_variables(bufnr))
      assert.equals(1, stats.total)
      assert.equals(1, stats.ignored)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should run registered checks for variables that survive policy and hooks', function()
      local checks = require('camouflage.checks')
      local badges = require('camouflage.checks.badges')
      config.setup({
        policy = {
          rules = {
            { id = 'ignore-debug', action = 'ignore', key = { '^DEBUG$' } },
          },
        },
        checks = {
          custom_policy = {
            label = 'custom',
          },
        },
      })
      check_registry.register({
        name = 'custom_policy',
        run = function(ctx)
          assert.equals('API_KEY', ctx.var.key)
          assert.equals('custom', ctx.config.label)
          return {
            severity = 'warning',
            text = '[custom]',
            hl_group = 'DiagnosticWarn',
            data = { key = ctx.var.key },
          }
        end,
      })
      local bufnr = setup_buffer({ 'DEBUG=true', 'API_KEY=secret' })
      checks.set_result(bufnr, 1, 'pwned', {
        severity = 'error',
        text = '[PWNED]',
        hl_group = 'DiagnosticError',
      })

      core.apply_decorations(bufnr)

      assert.is_nil(checks_store.get(bufnr, 0, 'custom_policy'))
      assert.is_table(checks_store.get(bufnr, 1, 'custom_policy'))
      assert.is_table(checks_store.get(bufnr, 1, 'pwned'))

      local marks = vim.api.nvim_buf_get_extmarks(
        bufnr,
        badges.get_namespace(),
        { 1, 0 },
        { 1, -1 },
        { details = true }
      )
      assert.equals('[PWNED]', marks[1][4].virt_text[1][1])
      assert.equals('[custom]', marks[1][4].virt_text[3][1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('compute_line_offsets', function()
    it('should compute correct offsets for single line', function()
      local lines = { 'hello' }
      local offsets = core.compute_line_offsets(lines)

      assert.equals(0, offsets[1])
      assert.equals(6, offsets[2]) -- 5 chars + 1 newline
    end)

    it('should compute correct offsets for multiple lines', function()
      local lines = { 'line1', 'line2', 'line3' }
      local offsets = core.compute_line_offsets(lines)

      assert.equals(0, offsets[1])
      assert.equals(6, offsets[2])
      assert.equals(12, offsets[3])
      assert.equals(18, offsets[4])
    end)

    it('should handle empty lines', function()
      local lines = { '', 'text', '' }
      local offsets = core.compute_line_offsets(lines)

      assert.equals(0, offsets[1])
      assert.equals(1, offsets[2])
      assert.equals(6, offsets[3])
    end)
  end)

  describe('refresh', function()
    it('should not error when called', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)

      assert.has_no.errors(function()
        core.refresh()
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('refresh_all', function()
    it('should not error when called', function()
      assert.has_no.errors(function()
        core.refresh_all()
      end)
    end)
  end)
end)
