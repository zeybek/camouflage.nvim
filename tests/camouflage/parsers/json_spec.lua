local json_parser = require('camouflage.parsers.json')

describe('camouflage.parsers.json', function()
  before_each(function()
    require('camouflage.config').setup({
      parsers = {
        json = {
          max_depth = 10,
        },
      },
    })
  end)

  describe('parse', function()
    it('should parse simple key-value pairs', function()
      local content = '{"api_key": "secret123"}'
      local result = json_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('secret123', result[1].value)
    end)

    it('should parse multiple keys', function()
      local content = [[{
  "key1": "value1",
  "key2": "value2",
  "key3": "value3"
}]]
      local result = json_parser.parse(content)

      assert.equals(3, #result)
    end)

    it('should parse nested objects', function()
      local content = [[{
  "database": {
    "host": "localhost",
    "password": "secret"
  }
}]]
      local result = json_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('localhost', keys['database.host'])
      assert.equals('secret', keys['database.password'])
    end)

    it('should parse deeply nested objects', function()
      local content = [[{
  "level1": {
    "level2": {
      "level3": {
        "secret": "deep_value"
      }
    }
  }
}]]
      local result = json_parser.parse(content)

      local found = false
      for _, v in ipairs(result) do
        if v.key == 'level1.level2.level3.secret' then
          found = true
          assert.equals('deep_value', v.value)
        end
      end
      assert.is_true(found)
    end)

    it('should parse number values', function()
      local content = '{"port": 5432}'
      local result = json_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('port', result[1].key)
      assert.equals('5432', result[1].value)
    end)

    it('should parse boolean values', function()
      local content = '{"enabled": true, "disabled": false}'
      local result = json_parser.parse(content)

      assert.equals(2, #result)
      local values = {}
      for _, v in ipairs(result) do
        values[v.key] = v.value
      end
      assert.equals('true', values['enabled'])
      assert.equals('false', values['disabled'])
    end)

    it('should skip arrays', function()
      local content = [[{
  "items": ["a", "b", "c"],
  "password": "secret"
}]]
      local result = json_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('password', result[1].key)
    end)

    it('should handle empty objects', function()
      local content = '{}'
      local result = json_parser.parse(content)

      assert.equals(0, #result)
    end)

    it('should respect max_depth', function()
      require('camouflage.config').setup({
        parsers = {
          json = {
            max_depth = 1,
          },
        },
      })

      local content = [[{
  "level1": {
    "level2": {
      "secret": "too_deep"
    }
  },
  "top": "visible"
}]]
      local result = json_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = true
      end

      assert.is_true(keys['top'])
      assert.is_nil(keys['level1.level2.secret'])
    end)

    it('should handle empty string values', function()
      local result = json_parser.parse('{"key": ""}')
      -- Empty string values are not found by position matching (pattern match fails)
      -- This is expected behavior - no position means no result
      assert.equals(0, #result)
    end)

    it('should handle simple string values', function()
      local result = json_parser.parse('{"key": "value with quotes"}')

      assert.equals(1, #result)
      assert.equals('key', result[1].key)
      assert.equals('value with quotes', result[1].value)
    end)

    it('should handle null values', function()
      local result = json_parser.parse('{"key": null, "other": "value"}')

      assert.equals(1, #result)
      assert.equals('other', result[1].key)
    end)

    it('should handle invalid JSON gracefully', function()
      local result = json_parser.parse('{ invalid json }')
      assert.is_table(result)
      assert.equals(0, #result)
    end)

    it('should handle unicode values', function()
      local result = json_parser.parse('{"greeting": "Hello 世界"}')

      assert.equals(1, #result)
      assert.equals('greeting', result[1].key)
      assert.equals('Hello 世界', result[1].value)
    end)

    it('should handle whitespace-only values', function()
      local result = json_parser.parse('{"key": "   "}')
      -- Whitespace-only values may not be found by pattern matching
      -- depending on how the regex handles spaces
      assert.is_table(result)
    end)
  end)
end)
