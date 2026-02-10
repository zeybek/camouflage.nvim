local toml_parser = require('camouflage.parsers.toml')

describe('camouflage.parsers.toml', function()
  before_each(function()
    require('camouflage.config').setup({
      parsers = {
        env = {
          include_commented = true,
        },
      },
    })
  end)

  describe('parse', function()
    it('should parse simple key-value pairs', function()
      local content = 'api_key = "secret123"'
      local result = toml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('secret123', result[1].value)
    end)

    it('should parse multiple keys', function()
      local content = [[
key1 = "value1"
key2 = "value2"
key3 = "value3"
]]
      local result = toml_parser.parse(content)

      assert.equals(3, #result)
    end)

    it('should parse sections', function()
      local content = [[
[database]
host = "localhost"
password = "secret"
]]
      local result = toml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('localhost', keys['database.host'])
      assert.equals('secret', keys['database.password'])
    end)

    it('should parse nested sections', function()
      local content = [[
[database.connection]
host = "localhost"
password = "secret"
]]
      local result = toml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('localhost', keys['database.connection.host'])
      assert.equals('secret', keys['database.connection.password'])
    end)

    it('should parse single quoted strings', function()
      local content = "password = 'my secret'"
      local result = toml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('my secret', result[1].value)
    end)

    it('should parse unquoted values', function()
      local content = 'port = 5432'
      local result = toml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('5432', result[1].value)
    end)

    it('should parse boolean values', function()
      local content = [[
enabled = true
disabled = false
]]
      local result = toml_parser.parse(content)

      assert.equals(2, #result)
    end)

    it('should handle array of tables', function()
      local content = '[' .. '[servers]' .. ']\nhost = "server1"\n'
      local result = toml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('servers.host', result[1].key)
    end)

    it('should handle inline comments', function()
      local content = 'password = "secret" # this is a comment'
      local result = toml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('secret', result[1].value)
    end)

    it('should handle empty content', function()
      local content = ''
      local result = toml_parser.parse(content)

      assert.equals(0, #result)
    end)

    it('should handle dotted keys', function()
      local content = 'database.password = "secret"'
      local result = toml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('database.password', result[1].key)
    end)
  end)
end)
