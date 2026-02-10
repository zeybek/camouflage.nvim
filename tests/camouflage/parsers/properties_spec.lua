local properties_parser = require('camouflage.parsers.properties')

describe('camouflage.parsers.properties', function()
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
    it('should parse simple key=value pairs', function()
      local content = 'api.key=secret123'
      local result = properties_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('api.key', result[1].key)
      assert.equals('secret123', result[1].value)
    end)

    it('should parse key: value pairs', function()
      local content = 'api.key: secret123'
      local result = properties_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('api.key', result[1].key)
      assert.equals('secret123', result[1].value)
    end)

    it('should parse multiple keys', function()
      local content = [[
key1=value1
key2=value2
key3=value3
]]
      local result = properties_parser.parse(content)

      assert.equals(3, #result)
    end)

    it('should parse sections', function()
      local content = [[
[database]
host=localhost
password=secret
]]
      local result = properties_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('localhost', keys['database.host'])
      assert.equals('secret', keys['database.password'])
    end)

    it('should handle spaces around separator', function()
      local content = 'password = secret'
      local result = properties_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('password', result[1].key)
      assert.equals('secret', result[1].value)
    end)

    it('should skip comment lines', function()
      local content = [[
# This is a comment
; This is also a comment
password=secret
]]
      local result = properties_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('password', result[1].key)
    end)

    it('should handle empty content', function()
      local content = ''
      local result = properties_parser.parse(content)

      assert.equals(0, #result)
    end)

    it('should handle values with equals sign', function()
      local content = 'connection=jdbc:mysql://localhost:3306/db?user=root'
      local result = properties_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('connection', result[1].key)
      -- Value should contain everything after the first =
      assert.is_true(result[1].value:find('jdbc:mysql') ~= nil)
    end)
  end)
end)
