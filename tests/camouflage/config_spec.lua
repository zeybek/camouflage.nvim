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

    it('should have default debounce_ms of 150', function()
      config.setup()
      assert.equals(150, config.get().debounce_ms)
    end)

    it('should allow custom debounce_ms', function()
      config.setup({ debounce_ms = 0 })
      assert.equals(0, config.get().debounce_ms)
    end)

    it('should include data-only policy defaults', function()
      config.setup()
      local policy = config.get().policy

      assert.is_table(policy)
      assert.is_true(policy.enabled)
      assert.equals('mask', policy.default_action)
      assert.same({}, policy.terminal_path_ignores)
      assert.same({}, policy.rules)
    end)

    it('keeps HIBP available but disables automatic network checks by default', function()
      config.setup()
      local pwned = config.get().pwned

      assert.is_true(pwned.enabled)
      assert.is_false(pwned.auto_check)
      assert.is_false(pwned.check_on_save)
      assert.is_false(pwned.check_on_change)
    end)

    it('allows opting in to individual HIBP automatic triggers', function()
      config.setup({
        pwned = {
          check_on_save = true,
        },
      })
      local pwned = config.get().pwned

      assert.is_false(pwned.auto_check)
      assert.is_true(pwned.check_on_save)
      assert.is_false(pwned.check_on_change)
    end)

    it('does not let legacy pwned aliasing mutate defaults across setup calls', function()
      config.setup()
      assert.is_nil(config.defaults.checks.pwned)

      config.setup({
        pwned = {
          auto_check = true,
        },
      })

      assert.is_nil(config.defaults.checks.pwned)
      assert.is_true(config.get().pwned.auto_check)
      assert.is_true(config.get().checks.pwned.auto_check)
    end)

    it('should merge user policy options with defaults', function()
      config.setup({
        policy = {
          terminal_path_ignores = { 'vendor/**' },
          rules = {
            { id = 'ignore-debug', action = 'ignore', key = { '^DEBUG$' } },
          },
        },
      })

      local policy = config.get().policy
      assert.is_true(policy.enabled)
      assert.equals('mask', policy.default_action)
      assert.same({ 'vendor/**' }, policy.terminal_path_ignores)
      assert.equals('ignore-debug', policy.rules[1].id)
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

    it('should update policy options with dot notation', function()
      config.setup()
      config.set('policy.enabled', false)
      assert.is_false(config.get().policy.enabled)
    end)

    it('should call refresh_all when value changes (hot reload)', function()
      config.setup({ style = 'stars' })

      local core = require('camouflage.core')
      local refresh_called = false
      local original_refresh = core.refresh_all
      core.refresh_all = function()
        refresh_called = true
      end

      config.set('style', 'dotted')

      vim.wait(100, function()
        return refresh_called
      end)

      assert.is_true(refresh_called)
      core.refresh_all = original_refresh
    end)

    it('should NOT call refresh_all when value is same', function()
      config.setup({ style = 'stars' })

      local core = require('camouflage.core')
      local refresh_called = false
      local original_refresh = core.refresh_all
      core.refresh_all = function()
        refresh_called = true
      end

      config.set('style', 'stars') -- Same value

      vim.wait(50, function()
        return refresh_called
      end)

      assert.is_false(refresh_called)
      core.refresh_all = original_refresh
    end)
  end)

  describe('get_style', function()
    it('should return current style', function()
      config.setup({ style = 'scramble' })
      assert.equals('scramble', config.get_style())
    end)
  end)

  describe('get_check', function()
    it('returns the canonical checks table for a name', function()
      config.setup({ pwned = { enabled = true } })
      assert.is_table(config.get_check('pwned'))
      -- pwned and checks.pwned are the same table (no drift possible)
      assert.equals(config.get().pwned, config.get_check('pwned'))
    end)

    it('returns an empty table for an unknown check', function()
      config.setup()
      assert.same({}, config.get_check('does_not_exist'))
    end)

    it('includes weak-secret defaults', function()
      config.setup()
      local weak_secret = config.get_check('weak_secret')
      assert.is_true(weak_secret.enabled)
      assert.equals(12, weak_secret.min_sensitive_length)
      assert.equals('[weak: %s]', weak_secret.virtual_text_format)
      assert.is_table(weak_secret.sensitive_key_patterns)
    end)

    it('returns custom registered-check configuration by name', function()
      config.setup({
        checks = {
          local_policy = {
            enabled = false,
            label = 'team',
          },
        },
      })

      local local_policy = config.get_check('local_policy')
      assert.is_false(local_policy.enabled)
      assert.equals('team', local_policy.label)
    end)
  end)

  describe('checks.pwned canonical namespace', function()
    it('lets checks.pwned override the legacy pwned key', function()
      config.setup({ pwned = { enabled = true }, checks = { pwned = { enabled = false } } })
      assert.is_false(config.get().pwned.enabled)
      assert.is_false(config.get_check('pwned').enabled)
    end)

    it('aliases pwned and checks.pwned to the same table', function()
      config.setup({ pwned = { auto_check = false } })
      assert.equals(config.get().pwned, config.get().checks.pwned)
    end)
  end)

  describe('set feedback', function()
    it('returns false on a missing intermediate path segment', function()
      config.setup()
      assert.is_false(config.set('nonexistent.deep.key', 1))
    end)

    it('returns true when the key path is valid', function()
      config.setup()
      assert.is_true(config.set('style', 'stars'))
    end)
  end)
end)
