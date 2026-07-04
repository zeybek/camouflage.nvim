local weak_secret = require('camouflage.checks.weak_secret')
local checks = require('camouflage.checks')
local badges = require('camouflage.checks.badges')
local config = require('camouflage.config')
local hooks = require('camouflage.hooks')
local store = require('camouflage.checks.store')
local state = require('camouflage.state')

local function parsed_var(key, value, line)
  return {
    key = key,
    value = value,
    line_number = line or 0,
    start_index = 0,
    end_index = #value,
    is_nested = false,
    is_commented = false,
  }
end

local function fresh_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { 'SECRET_KEY=changeme' })
  return bufnr
end

local function get_badge_mark(bufnr, lnum)
  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    badges.get_namespace(),
    { lnum, 0 },
    { lnum, -1 },
    { details = true }
  )
  return marks[1]
end

describe('camouflage.checks.weak_secret', function()
  before_each(function()
    weak_secret.teardown()
    hooks.clear()
    config.setup()
    store._reset()
    state.clear()
    weak_secret._reset_warnings()
    weak_secret.setup()
  end)

  after_each(function()
    weak_secret.teardown()
    hooks.clear()
  end)

  describe('classify', function()
    it('flags conservative weak secret categories', function()
      local cases = {
        { parsed_var('PASSWORD', 'password'), 'default' },
        { parsed_var('API_KEY', 'replace_me'), 'placeholder' },
        { parsed_var('SECRET', 'aaaaaaaaaaaa'), 'repeated' },
        { parsed_var('TOKEN', '12345678'), 'sequence' },
        { parsed_var('SECRET_KEY', 'abcDEF123'), 'short' },
        { parsed_var('TOKEN', 'abcabcabcabcabcabc'), 'entropy' },
      }

      for _, case in ipairs(cases) do
        local result = weak_secret.classify(case[1])
        assert.is_table(result)
        assert.equals(case[2], result.reason)
      end
    end)

    it('uses key context to skip benign config values and strong tokens', function()
      assert.is_nil(weak_secret.classify(parsed_var('PORT', '5432')))
      assert.is_nil(weak_secret.classify(parsed_var('DEBUG', 'true')))
      assert.is_nil(
        weak_secret.classify(parsed_var('API_KEY', 'strong-token-value-51NzUtRPAJ7QH9KtVwxyZM123'))
      )
    end)

    it('honors ignored key and value patterns without disabling the check', function()
      local cfg = vim.tbl_deep_extend('force', {}, config.get_check('weak_secret'), {
        ignored_key_patterns = { '^PASSWORD$' },
      })
      assert.is_nil(weak_secret.classify(parsed_var('PASSWORD', 'password'), cfg))

      cfg = vim.tbl_deep_extend('force', {}, config.get_check('weak_secret'), {
        ignored_value_patterns = { '^changeme$' },
      })
      assert.is_nil(weak_secret.classify(parsed_var('SECRET_KEY', 'changeme'), cfg))
    end)

    it('honors configured length thresholds', function()
      local cfg = vim.tbl_deep_extend('force', {}, config.get_check('weak_secret'), {
        min_sensitive_length = 8,
      })
      assert.is_nil(weak_secret.classify(parsed_var('SECRET_KEY', 'abcDEF123'), cfg))

      cfg = vim.tbl_deep_extend('force', {}, config.get_check('weak_secret'), {
        min_length = 20,
        min_sensitive_length = 8,
      })
      assert.is_nil(weak_secret.classify(parsed_var('TOKEN', 'abcabcabcabcabcabc'), cfg))
    end)

    it('skips invalid Lua patterns without throwing', function()
      local original_notify = vim.notify
      vim.notify = function() end

      local cfg = vim.tbl_deep_extend('force', {}, config.get_check('weak_secret'), {
        ignored_key_patterns = { '[' },
      })
      local result
      assert.has_no.errors(function()
        result = weak_secret.classify(parsed_var('PASSWORD', 'password'), cfg)
      end)

      vim.notify = original_notify
      assert.is_table(result)
      assert.equals('default', result.reason)
    end)

    it('classifies one thousand variables quickly enough for decoration', function()
      local vars = {}
      for i = 1, 1000 do
        vars[i] = parsed_var('TOKEN_' .. i, 'abcabcabcabcabcabc')
      end

      local start = (vim.uv or vim.loop).hrtime()
      for _, var in ipairs(vars) do
        weak_secret.classify(var)
      end
      local elapsed_ms = ((vim.uv or vim.loop).hrtime() - start) / 1000000

      assert.is_true(
        elapsed_ms < 500,
        string.format('expected 1000 classifications under 500ms, got %.2fms', elapsed_ms)
      )
    end)
  end)

  describe('hook integration', function()
    it('adds a redacted weak-secret badge for parsed variables', function()
      local bufnr = fresh_buffer({ 'SECRET_KEY=replace_me' })
      hooks.emit('before_decorate', bufnr, '.env')
      hooks.emit('variable_detected', bufnr, parsed_var('SECRET_KEY', 'replace_me', 0))

      local result = store.get(bufnr, 0, 'weak_secret')
      assert.is_table(result)
      assert.equals('[weak: placeholder]', result.text)
      assert.equals('placeholder', result.data.reason)
      assert.equals(#'replace_me', result.data.value_length)
      assert.is_nil(result.data.value)
      assert.is_nil(result.text:find('replace_me', 1, true))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('clears stale weak-secret results on each decoration cycle', function()
      local bufnr = fresh_buffer()
      hooks.emit('before_decorate', bufnr, '.env')
      hooks.emit('variable_detected', bufnr, parsed_var('PASSWORD', 'password', 0))
      assert.is_table(store.get(bufnr, 0, 'weak_secret'))

      hooks.emit('before_decorate', bufnr, '.env')
      hooks.emit(
        'variable_detected',
        bufnr,
        parsed_var('PASSWORD', 'VeryStrongSecretValue123!@#', 0)
      )
      assert.is_nil(store.get(bufnr, 0, 'weak_secret'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('composes with pwned and expiry badges on the same line', function()
      local bufnr = fresh_buffer()
      checks.set_result(bufnr, 0, 'pwned', {
        severity = 'error',
        text = '[PWNED]',
        hl_group = 'DiagnosticError',
      })
      hooks.emit('variable_detected', bufnr, parsed_var('PASSWORD', 'password', 0))
      checks.set_result(bufnr, 0, 'expiry', {
        severity = 'warning',
        text = '[expires]',
        hl_group = 'DiagnosticWarn',
      })

      local mark = get_badge_mark(bufnr, 0)
      assert.is_table(mark)
      assert.equals('[PWNED]', mark[4].virt_text[1][1])
      assert.equals('[weak: default]', mark[4].virt_text[3][1])
      assert.equals('[expires]', mark[4].virt_text[5][1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('check_buffer recomputes from current parsed state', function()
      local bufnr = fresh_buffer()
      state.set_variables(bufnr, { parsed_var('PASSWORD', 'password', 0) })

      weak_secret.check_buffer(bufnr)

      assert.is_table(store.get(bufnr, 0, 'weak_secret'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
