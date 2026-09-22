local env_parser = require('camouflage.parsers.env')

describe('camouflage.parsers.env', function()
  -- Setup config before tests
  before_each(function()
    require('camouflage.config').setup({
      parsers = {
        env = {
          include_commented = true,
          include_export = true,
        },
      },
    })
  end)

  describe('parse', function()
    it('should parse simple KEY=value', function()
      local content = 'API_KEY=secret123'
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('API_KEY', result[1].key)
      assert.equals('secret123', result[1].value)
      assert.equals(0, result[1].line_number)
      assert.is_false(result[1].is_commented)
    end)

    it('should parse export KEY=value', function()
      local content = 'export DATABASE_URL=postgres://localhost'
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('DATABASE_URL', result[1].key)
      assert.equals('postgres://localhost', result[1].value)
    end)

    it('parses assignments behind readonly, declare, typeset and local', function()
      local content = table.concat({
        'readonly API_TOKEN="readonly_secret_1"',
        'declare -x DB_PASSWORD=declare_secret_2',
        '  local PASSWORD="local_secret_3"',
        'typeset -r SECRET_KEY=typeset_secret_4',
        'declare -gx -r MULTI=multi_flag_5',
      }, '\n')
      local result = env_parser.parse(content)

      assert.equals(5, #result)
      local expected = {
        { 'API_TOKEN', 'readonly_secret_1' },
        { 'DB_PASSWORD', 'declare_secret_2' },
        { 'PASSWORD', 'local_secret_3' },
        { 'SECRET_KEY', 'typeset_secret_4' },
        { 'MULTI', 'multi_flag_5' },
      }
      for i, want in ipairs(expected) do
        assert.equals(want[1], result[i].key)
        assert.equals(want[2], result[i].value)
        -- The range points at the value itself in the original text.
        assert.equals(want[2], content:sub(result[i].start_index + 1, result[i].end_index))
      end
    end)

    it('parses dotted and dashed keys in a dotenv file', function()
      local content =
        'app.secret=dotted_value\nMY-TOKEN=dash_value\nspring.datasource.password=hunter2'
      local result = env_parser.parse(content, nil, '/repo/.env')

      assert.equals(3, #result)
      assert.equals('app.secret', result[1].key)
      assert.equals('MY-TOKEN', result[2].key)
      assert.equals('spring.datasource.password', result[3].key)
      assert.equals('hunter2', content:sub(result[3].start_index + 1, result[3].end_index))
    end)

    it('parses them when no filename is given, as for a dotenv file', function()
      local result = env_parser.parse('app.secret=dotted_value')

      assert.equals(1, #result)
      assert.equals('app.secret', result[1].key)
    end)

    it('keeps shell names in shell scripts and .envrc', function()
      local content = 'app.secret=dotted_value\nMY-TOKEN=dash_value\nREAL=value'
      for _, filename in ipairs({ '/repo/deploy.sh', '/repo/.envrc' }) do
        local result = env_parser.parse(content, nil, filename)

        assert.equals(1, #result, filename)
        assert.equals('REAL', result[1].key)
      end
    end)

    it('does not take a name that starts like a declaration for one', function()
      local result = env_parser.parse(
        'local_var=plain_value\nreadonly_mode=true\nlocal\ndeclare -a arr\nlocal value = 42'
      )

      assert.equals(2, #result)
      assert.equals('local_var', result[1].key)
      assert.equals('readonly_mode', result[2].key)
    end)

    it('should parse multiple lines', function()
      local content = [[
API_KEY=key1
SECRET=secret2
TOKEN=token3
]]
      local result = env_parser.parse(content)

      assert.equals(3, #result)
      assert.equals('API_KEY', result[1].key)
      assert.equals('SECRET', result[2].key)
      assert.equals('TOKEN', result[3].key)
    end)

    it('should handle quoted values', function()
      local content = 'MESSAGE="Hello World"'
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('Hello World', result[1].value)
    end)

    it('should handle single quoted values', function()
      local content = "PASSWORD='my secret'"
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('my secret', result[1].value)
    end)

    it('should skip empty values', function()
      local content = [[
API_KEY=
SECRET=actual_secret
EMPTY=
]]
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('SECRET', result[1].key)
    end)

    it('should parse commented lines when enabled', function()
      local content = '# OLD_KEY=old_value'
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('OLD_KEY', result[1].key)
      assert.is_true(result[1].is_commented)
    end)

    it('should handle indented export statements', function()
      local content = '  export MY_VAR=value'
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('MY_VAR', result[1].key)
    end)

    it('should handle empty file', function()
      local result = env_parser.parse('')
      assert.are.same({}, result)
    end)

    it('should handle whitespace only values', function()
      local result = env_parser.parse('KEY=   ')
      -- Whitespace-only values should be skipped (treated as empty)
      assert.equals(0, #result)
    end)

    it('should handle line without equals sign', function()
      local result = env_parser.parse('INVALID_LINE')
      assert.are.same({}, result)
    end)

    it('should handle multiple equals signs in value', function()
      local result = env_parser.parse('DATABASE_URL=postgres://user:pass@host/db?param=value')

      assert.equals(1, #result)
      assert.equals('DATABASE_URL', result[1].key)
      assert.equals('postgres://user:pass@host/db?param=value', result[1].value)
    end)

    it('should handle values with special characters', function()
      local result = env_parser.parse('PASSWORD="p@ss$w0rd!#%^&*()"')

      assert.equals(1, #result)
      assert.equals('PASSWORD', result[1].key)
      assert.equals('p@ss$w0rd!#%^&*()', result[1].value)
    end)

    it('should handle only comments', function()
      local content = [[
# This is a comment
# Another comment
]]
      local result = env_parser.parse(content)
      -- Commented lines with KEY=value format are parsed when include_commented is true
      -- Plain comments without = should not produce results
      assert.equals(0, #result)
    end)
  end)

  describe('multiline values', function()
    local function slice(content, var)
      return content:sub(var.start_index + 1, var.end_index)
    end

    it('spans a double-quoted value over the following lines', function()
      local content = table.concat({
        'PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----',
        'MIIEowIBAAKCAQEA7secretbody',
        '-----END RSA PRIVATE KEY-----"',
      }, '\n')
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('PRIVATE_KEY', result[1].key)
      assert.is_true(result[1].is_multiline)
      assert.equals(
        '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA7secretbody\n-----END RSA PRIVATE KEY-----',
        result[1].value
      )
      assert.equals(result[1].value, slice(content, result[1]))
      assert.equals(0, result[1].line_number)
    end)

    it('supports single quotes and backticks like dotenv', function()
      local content = "A='one\ntwo'\nB=`three\nfour`"
      local result = env_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('one\ntwo', result[1].value)
      assert.equals('one\ntwo', slice(content, result[1]))
      assert.equals('B', result[2].key)
      assert.equals('three\nfour', result[2].value)
      assert.equals('three\nfour', slice(content, result[2]))
    end)

    it('ignores escaped quotes when looking for the end of the value', function()
      local content = 'TOKEN="first \\" still open\nsecond"'
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('first \\" still open\nsecond', result[1].value)
      assert.equals(result[1].value, slice(content, result[1]))
    end)

    it('keeps parsing keys after the multiline value with correct offsets', function()
      local content = 'KEY="line1\nline2"\nNEXT=after\n'
      local result = env_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('NEXT', result[2].key)
      assert.equals('after', slice(content, result[2]))
      assert.equals(2, result[2].line_number)
    end)

    it('does not treat KEY=value lines inside the quotes as separate variables', function()
      local content = 'CERT="begin\nINNER=notakey\nend"'
      local result = env_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('CERT', result[1].key)
    end)

    it('leaves a quote that never closes as a single-line value', function()
      local content = 'BROKEN="no closing quote\nOTHER=value'
      local result = env_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('"no closing quote', result[1].value)
      assert.is_nil(result[1].is_multiline)
      assert.equals('OTHER', result[2].key)
    end)
  end)
end)
