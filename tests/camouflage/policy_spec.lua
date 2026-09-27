local config = require('camouflage.config')

local function parsed_var(key, value, line)
  return {
    key = key,
    value = value,
    line_number = line or 0,
    start_index = 0,
    end_index = #tostring(value or ''),
    is_nested = false,
    is_commented = false,
  }
end

local function context(var, opts)
  opts = opts or {}
  return {
    filename = opts.filename or '/repo/app.env',
    root = opts.root or '/repo',
    parser_name = opts.parser_name or 'env',
    variable = var,
  }
end

describe('camouflage.policy', function()
  local policy

  before_each(function()
    package.loaded['camouflage.policy'] = nil
    policy = require('camouflage.policy')
    policy._reset_warnings()
    config.setup()
  end)

  describe('evaluate', function()
    it('defaults to masking when no rules are configured', function()
      local decision = policy.evaluate(context(parsed_var('API_KEY', 'secret')))

      assert.equals('mask', decision.action)
      assert.equals('default', decision.reason)
      assert.is_nil(decision.rule_id)
    end)

    it('applies ordered ignore and mask rules deterministically', function()
      local cfg = {
        enabled = true,
        default_action = 'mask',
        rules = {
          {
            id = 'ignore-debug',
            action = 'ignore',
            key = { '^DEBUG$' },
          },
          {
            id = 'mask-client-secret',
            action = 'mask',
            key = { 'CLIENT_SECRET' },
          },
        },
      }

      local ignored = policy.evaluate(context(parsed_var('DEBUG', 'true')), cfg)
      local masked = policy.evaluate(context(parsed_var('CLIENT_SECRET', 'secret')), cfg)
      local inherited = policy.evaluate(context(parsed_var('API_KEY', 'secret')), cfg)

      assert.equals('ignore', ignored.action)
      assert.equals('rule', ignored.reason)
      assert.equals('ignore-debug', ignored.rule_id)
      assert.equals('mask', masked.action)
      assert.equals('mask-client-secret', masked.rule_id)
      assert.equals('mask', inherited.action)
      assert.equals('default', inherited.reason)
    end)

    it('lets explicit force-mask rules override broad ignores', function()
      local cfg = {
        rules = {
          {
            id = 'ignore-fixtures',
            action = 'ignore',
            path = { 'tests/fixtures/**' },
          },
          {
            id = 'force-client-secret',
            action = 'mask',
            key = { '^CLIENT_SECRET$' },
            allow_force = true,
          },
        },
      }

      local ignored = policy.evaluate(
        context(parsed_var('API_KEY', 'fixture-secret'), {
          filename = '/repo/tests/fixtures/app.env',
        }),
        cfg
      )
      local forced = policy.evaluate(
        context(parsed_var('CLIENT_SECRET', 'fixture-secret'), {
          filename = '/repo/tests/fixtures/app.env',
        }),
        cfg
      )

      assert.equals('ignore', ignored.action)
      assert.equals('ignore-fixtures', ignored.rule_id)
      assert.equals('mask', forced.action)
      assert.equals('force-client-secret', forced.rule_id)
    end)

    it('applies terminal path ignores unless an allow_force mask rule matches', function()
      local cfg = {
        terminal_path_ignores = { 'vendor/**' },
        rules = {
          {
            id = 'force-private-key',
            action = 'mask',
            key = { 'PRIVATE_KEY' },
            allow_force = true,
          },
        },
      }

      local ignored = policy.evaluate(
        context(parsed_var('TOKEN', 'vendor-token'), { filename = '/repo/vendor/app.env' }),
        cfg
      )
      local forced = policy.evaluate(
        context(parsed_var('PRIVATE_KEY', 'vendor-key'), { filename = '/repo/vendor/app.env' }),
        cfg
      )

      assert.equals('ignore', ignored.action)
      assert.equals('terminal_path_ignore', ignored.reason)
      assert.equals('mask', forced.action)
      assert.equals('force-private-key', forced.rule_id)
    end)

    it('matches path, basename, parser, key, nested, commented, and value predicates', function()
      local var = parsed_var('database.password', '"abc123TOKEN"', 0)
      var.is_nested = true
      var.is_commented = false

      local cfg = {
        rules = {
          {
            id = 'ignore-json-test-token',
            action = 'ignore',
            path = { 'config/*.json' },
            basename = { 'app.json' },
            parser = { 'json' },
            key = { 'database%.password' },
            nested = true,
            commented = false,
            value_length = { min = 8, max = 32 },
            value_shape = { 'quoted', 'token_like' },
            value_prefix = { '"' },
            value_suffix = { '"' },
          },
        },
      }

      local decision = policy.evaluate(
        context(var, {
          filename = '/repo/config/app.json',
          parser_name = 'json',
        }),
        cfg
      )

      assert.equals('ignore', decision.action)
      assert.equals('ignore-json-test-token', decision.rule_id)
    end)

    it('supports safe value-shape predicates without exposing values in warnings', function()
      local cfg = {
        rules = {
          { id = 'empty', action = 'ignore', value_shape = { 'empty' } },
          { id = 'number', action = 'ignore', value_shape = { 'numeric' } },
          { id = 'boolean', action = 'ignore', value_shape = { 'boolean' } },
          { id = 'jwt', action = 'ignore', value_shape = { 'jwt_like' } },
        },
      }

      assert.equals('empty', policy.evaluate(context(parsed_var('A', '')), cfg).rule_id)
      assert.equals('number', policy.evaluate(context(parsed_var('A', '5432')), cfg).rule_id)
      assert.equals('boolean', policy.evaluate(context(parsed_var('A', 'false')), cfg).rule_id)
      assert.equals('jwt', policy.evaluate(context(parsed_var('A', 'aaa.bbb.ccc')), cfg).rule_id)
    end)

    it('skips invalid rules with one redacted warning and preserves masking', function()
      local calls = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(calls, { msg = msg, level = level })
      end

      local cfg = {
        rules = {
          {
            id = 'bad-secret-rule',
            action = 'drop',
            key = { 'SECRET' },
          },
        },
      }
      local decision = policy.evaluate(context(parsed_var('SECRET', 'plaintext-secret')), cfg)
      local second = policy.evaluate(context(parsed_var('SECRET', 'plaintext-secret')), cfg)

      vim.notify = original_notify

      assert.equals('mask', decision.action)
      assert.equals('mask', second.action)
      assert.equals(1, #calls)
      assert.equals(vim.log.levels.WARN, calls[1].level)
      assert.is_nil(calls[1].msg:find('plaintext-secret', 1, true))
    end)
  end)

  describe('ignore_case', function()
    local function decide(key, rule, default_action)
      local cfg = { default_action = default_action or 'mask', rules = { rule } }
      return policy.evaluate(context(parsed_var(key, 'value')), cfg)
    end

    it('leaves key patterns case-sensitive by default', function()
      local rule = { id = 'lower', action = 'ignore', key = { 'password' } }

      assert.equals('lower', decide('db_password', rule).rule_id)
      assert.equals('default', decide('DB_PASSWORD', rule).reason)
    end)

    it('matches a lower-case pattern in any case', function()
      local rule = { id = 'any-case', action = 'ignore', ignore_case = true, key = { 'password' } }

      for _, key in ipairs({ 'db_password', 'DB_PASSWORD', 'DbPassword' }) do
        assert.equals('any-case', decide(key, rule).rule_id, key)
      end
      assert.equals('default', decide('DB_PASSWD', rule).reason)
    end)

    it('masks upper-case keys under default_action ignore', function()
      local rule =
        { id = 'mask-secrets', action = 'mask', ignore_case = true, key = { 'password', 'token' } }

      assert.equals('mask', decide('DB_PASSWORD', rule, 'ignore').action)
      assert.equals('mask', decide('API_TOKEN', rule, 'ignore').action)
      assert.equals('ignore', decide('LOG_LEVEL', rule, 'ignore').action)
    end)

    it('compares an exact key in any case', function()
      local exact =
        { id = 'exact', action = 'ignore', ignore_case = true, key = { '^DB_PASSWORD$' } }
      local strict = { id = 'strict', action = 'ignore', key = { '^DB_PASSWORD$' } }

      assert.equals('exact', decide('db_password', exact).rule_id)
      assert.equals('exact', decide('Db_Password', exact).rule_id)
      assert.equals('default', decide('db_password', strict).reason)
    end)

    it('does not change what a character class means', function()
      local rule = { id = 'upper', action = 'ignore', ignore_case = true, key = { '^%u+_TOKEN$' } }

      assert.equals('upper', decide('API_TOKEN', rule).rule_id)
      assert.equals('default', decide('api_token', rule).reason)
    end)

    it('drops a rule whose ignore_case is not a boolean, with a warning', function()
      local calls = {}
      local original_notify = vim.notify
      vim.notify = function(msg)
        table.insert(calls, msg)
      end
      local decision = decide(
        'db_password',
        { id = 'bad', action = 'ignore', ignore_case = 'yes', key = { 'password' } }
      )
      vim.notify = original_notify

      assert.equals('mask', decision.action)
      assert.equals(1, #calls)
      assert.truthy(calls[1]:find('ignore_case must be boolean', 1, true), calls[1])
    end)
  end)

  describe('filter_variables', function()
    it('returns masked variables with redacted policy stats', function()
      local variables = {
        parsed_var('DEBUG', 'true'),
        parsed_var('API_KEY', 'secret'),
      }
      local filtered, result = policy.filter_variables({
        filename = '/repo/app.env',
        root = '/repo',
        parser_name = 'env',
        variables = variables,
        config = {
          policy = {
            rules = {
              { id = 'ignore-debug', action = 'ignore', key = { '^DEBUG$' } },
            },
          },
        },
      })

      assert.equals(1, #filtered)
      assert.equals('API_KEY', filtered[1].key)
      assert.equals(2, result.stats.total)
      assert.equals(1, result.stats.ignored)
      assert.equals(1, result.stats.masked)
      assert.is_false(vim.inspect(result):find('secret', 1, true) ~= nil)
    end)

    it(
      'classifies one thousand variables against one hundred rules without pathological slowdown',
      function()
        local rules = {}
        for i = 1, 100 do
          rules[i] = {
            id = 'rule-' .. i,
            action = i == 100 and 'ignore' or 'mask',
            key = { '^RULE_' .. i .. '$' },
          }
        end

        local variables = {}
        for i = 1, 1000 do
          variables[i] = parsed_var('RULE_100', 'token-value-' .. i)
        end

        -- CPU time of this process, not wall-clock time: the other specs run
        -- in parallel and would count against the budget.
        local start = os.clock()
        local filtered = policy.filter_variables({
          filename = '/repo/app.env',
          root = '/repo',
          parser_name = 'env',
          variables = variables,
          config = {
            policy = {
              rules = rules,
            },
          },
        })
        local elapsed_ms = (os.clock() - start) * 1000
        local budget_ms = 100

        assert.equals(0, #filtered)
        assert.is_true(
          elapsed_ms < budget_ms,
          string.format(
            'expected 100 rules x 1000 variables under %dms, got %.2fms',
            budget_ms,
            elapsed_ms
          )
        )
      end
    )
  end)
end)
