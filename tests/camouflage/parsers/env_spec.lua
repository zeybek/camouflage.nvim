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
end)
