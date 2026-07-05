local registry = require('camouflage.checks.registry')
local store = require('camouflage.checks.store')
local state = require('camouflage.state')
local config = require('camouflage.config')

local function fresh_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '.env')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { 'API_KEY=secret-value' })
  return bufnr
end

local function parsed_var(key, value, line)
  return {
    key = key,
    value = value,
    line_number = line or 0,
    start_index = 8,
    end_index = 8 + #value,
    is_nested = false,
    is_commented = false,
  }
end

local function run_checks(bufnr, variables, cfg)
  state.update_buffer(bufnr, {
    enabled = true,
    variables = variables,
    parser = 'env',
  })
  local run_id = registry.begin_decorate(bufnr)
  registry.run({
    bufnr = bufnr,
    filename = vim.api.nvim_buf_get_name(bufnr),
    parser_name = 'env',
    variables = variables,
    config = cfg or config.get(),
    run_id = run_id,
  })
  return run_id
end

describe('camouflage.checks.registry', function()
  before_each(function()
    registry._reset()
    store._reset()
    state.clear()
    config.setup()
  end)

  describe('registration', function()
    it('registers, lists, gets, and unregisters checks', function()
      registry.register({
        name = 'local_policy',
        priority = 80,
        run = function() end,
      })
      registry.register({
        name = 'org_policy',
        priority = 90,
        default_enabled = false,
        run = function() end,
      })

      local listed = registry.list()
      assert.equals('org_policy', listed[1].name)
      assert.equals('local_policy', listed[2].name)
      assert.is_true(listed[2].default_enabled)
      assert.is_false(listed[1].default_enabled)

      local fetched = registry.get('local_policy')
      assert.is_table(fetched)
      assert.equals('local_policy', fetched.name)

      assert.is_true(registry.unregister('local_policy'))
      assert.is_nil(registry.get('local_policy'))
      assert.is_false(registry.unregister('local_policy'))
    end)

    it('rejects invalid specs and duplicate names', function()
      assert.has.errors(function()
        registry.register({})
      end)
      assert.has.errors(function()
        registry.register({ name = 'bad/name', run = function() end })
      end)
      assert.has.errors(function()
        registry.register({ name = 'no_run' })
      end)

      registry.register({ name = 'duplicate', run = function() end })
      assert.has.errors(function()
        registry.register({ name = 'duplicate', run = function() end })
      end)
    end)

    it('clears rendered results when a check is unregistered', function()
      local bufnr = fresh_buffer()
      registry.register({
        name = 'cleanup_check',
        run = function()
          return { severity = 'info', text = '[cleanup]' }
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })
      assert.is_table(store.get(bufnr, 0, 'cleanup_check'))

      registry.unregister('cleanup_check')
      assert.is_nil(store.get(bufnr, 0, 'cleanup_check'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('synchronous checks', function()
    it('runs enabled checks with useful context and stores redacted results', function()
      local bufnr = fresh_buffer()
      local seen_ctx
      config.setup({
        checks = {
          local_policy = {
            enabled = true,
            label = 'org',
          },
        },
      })
      registry.register({
        name = 'local_policy',
        run = function(ctx)
          seen_ctx = ctx
          return {
            severity = 'warning',
            text = '[' .. ctx.config.label .. ']',
            hl_group = 'DiagnosticWarn',
            data = { key = ctx.var.key, value_length = #ctx.var.value },
          }
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })

      assert.equals(bufnr, seen_ctx.bufnr)
      assert.equals('env', seen_ctx.parser_name)
      assert.equals('API_KEY', seen_ctx.var.key)
      assert.equals('org', seen_ctx.config.label)
      assert.is_number(seen_ctx.run_id)
      assert.equals('local_policy', seen_ctx.check_name)

      local result = store.get(bufnr, 0, 'local_policy')
      assert.is_table(result)
      assert.equals('[org]', result.text)
      assert.equals('API_KEY', result.data.key)
      assert.equals(#'secret-value', result.data.value_length)
      assert.is_nil(result.text:find('secret-value', 1, true))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('skips checks disabled through checks.<name>.enabled', function()
      local bufnr = fresh_buffer()
      config.setup({ checks = { local_policy = { enabled = false } } })
      registry.register({
        name = 'local_policy',
        run = function()
          return { severity = 'warning', text = '[local]' }
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })

      assert.is_nil(store.get(bufnr, 0, 'local_policy'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('uses default_enabled unless config overrides it', function()
      local bufnr = fresh_buffer()
      registry.register({
        name = 'opt_in_check',
        default_enabled = false,
        run = function()
          return { severity = 'info', text = '[opt-in]' }
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })
      assert.is_nil(store.get(bufnr, 0, 'opt_in_check'))

      config.setup({ checks = { opt_in_check = { enabled = true } } })
      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })
      assert.is_table(store.get(bufnr, 0, 'opt_in_check'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('isolates crashing checks so later checks and masking continue', function()
      local bufnr = fresh_buffer()
      registry.register({
        name = 'crashing_check',
        priority = 100,
        run = function()
          error('boom')
        end,
      })
      registry.register({
        name = 'healthy_check',
        priority = 10,
        run = function()
          return { severity = 'info', text = '[healthy]' }
        end,
      })

      assert.has_no.errors(function()
        run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })
      end)
      assert.is_table(store.get(bufnr, 0, 'healthy_check'))
      assert.is_nil(store.get(bufnr, 0, 'crashing_check'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('redacts plaintext values from debug failure logs', function()
      local bufnr = fresh_buffer()
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      config.setup({ debug = true })
      registry.register({
        name = 'crashing_check',
        run = function(ctx)
          error('failed for ' .. ctx.var.value)
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })

      vim.notify = original_notify
      local combined = vim.inspect(notifications)
      assert.is_nil(combined:find('secret-value', 1, true))
      assert.is_not_nil(combined:find('%[redacted%]'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('drops invalid results and exact plaintext leaks', function()
      local bufnr = fresh_buffer()
      registry.register({
        name = 'invalid_check',
        run = function()
          return { severity = 'critical', text = '[bad]' }
        end,
      })
      registry.register({
        name = 'text_leak',
        run = function(ctx)
          return { severity = 'error', text = 'leaked ' .. ctx.var.value }
        end,
      })
      registry.register({
        name = 'data_leak',
        run = function(ctx)
          return { severity = 'error', text = '[leak]', data = { raw = ctx.var.value } }
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })

      assert.is_nil(store.get(bufnr, 0, 'invalid_check'))
      assert.is_nil(store.get(bufnr, 0, 'text_leak'))
      assert.is_nil(store.get(bufnr, 0, 'data_leak'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('asynchronous checks', function()
    it('publishes async results through the completion callback', function()
      local bufnr = fresh_buffer()
      local complete
      registry.register({
        name = 'remote_policy',
        async = true,
        run = function(_, done)
          complete = done
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })
      complete({ severity = 'warning', text = '[remote]' })

      vim.wait(100, function()
        return store.get(bufnr, 0, 'remote_policy') ~= nil
      end)
      assert.equals('[remote]', store.get(bufnr, 0, 'remote_policy').text)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('ignores old async results after a newer run supersedes them', function()
      local bufnr = fresh_buffer()
      local completions = {}
      registry.register({
        name = 'remote_policy',
        async = true,
        run = function(_, done)
          table.insert(completions, done)
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })
      run_checks(bufnr, { parsed_var('API_KEY', 'new-secret') })

      completions[1]({ severity = 'warning', text = '[old]' })
      completions[2]({ severity = 'warning', text = '[new]' })

      vim.wait(100, function()
        local result = store.get(bufnr, 0, 'remote_policy')
        return result and result.text == '[new]'
      end)
      assert.equals('[new]', store.get(bufnr, 0, 'remote_policy').text)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('ignores async results after the buffer changes before completion', function()
      local bufnr = fresh_buffer()
      local complete
      registry.register({
        name = 'remote_policy',
        async = true,
        run = function(_, done)
          complete = done
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'API_KEY=changed' })
      complete({ severity = 'warning', text = '[stale]' })

      vim.wait(50, function()
        return store.get(bufnr, 0, 'remote_policy') ~= nil
      end)
      assert.is_nil(store.get(bufnr, 0, 'remote_policy'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('ignores async results after unregister or buffer deletion', function()
      local bufnr = fresh_buffer()
      local complete
      registry.register({
        name = 'remote_policy',
        async = true,
        run = function(_, done)
          complete = done
        end,
      })

      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })
      registry.unregister('remote_policy')
      complete({ severity = 'warning', text = '[gone]' })
      vim.wait(50, function()
        return store.get(bufnr, 0, 'remote_policy') ~= nil
      end)
      assert.is_nil(store.get(bufnr, 0, 'remote_policy'))

      registry.register({
        name = 'remote_policy',
        async = true,
        run = function(_, done)
          complete = done
        end,
      })
      run_checks(bufnr, { parsed_var('API_KEY', 'secret-value') })
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.has_no.errors(function()
        complete({ severity = 'warning', text = '[deleted]' })
        vim.wait(20, function()
          return false
        end)
      end)
    end)
  end)
end)
