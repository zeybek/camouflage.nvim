local yaml_parser = require('camouflage.parsers.yaml')

describe('camouflage.parsers.yaml', function()
  before_each(function()
    require('camouflage.config').setup({
      parsers = {
        yaml = {
          max_depth = 10,
        },
        env = {
          include_commented = true,
        },
      },
    })
  end)

  describe('parse', function()
    it('should parse simple key-value pairs', function()
      local content = 'api_key: secret123'
      local result = yaml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('secret123', result[1].value)
    end)

    it('should parse multiple keys', function()
      local content = [[
key1: value1
key2: value2
key3: value3
]]
      local result = yaml_parser.parse(content)

      assert.equals(3, #result)
    end)

    it('should parse nested objects', function()
      local content = [[
database:
  host: localhost
  password: secret
]]
      local result = yaml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('localhost', keys['database.host'])
      assert.equals('secret', keys['database.password'])
    end)

    it('should parse deeply nested objects', function()
      local content = [[
level1:
  level2:
    level3:
      secret: deep_value
]]
      local result = yaml_parser.parse(content)

      local found = false
      for _, v in ipairs(result) do
        if v.key == 'level1.level2.level3.secret' then
          found = true
          assert.equals('deep_value', v.value)
        end
      end
      assert.is_true(found)
    end)

    it('should handle quoted strings', function()
      local content = 'message: "Hello World"'
      local result = yaml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('Hello World', result[1].value)
    end)

    it('should handle single quoted strings', function()
      local content = "password: 'my secret'"
      local result = yaml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('my secret', result[1].value)
    end)

    it('should skip document separators', function()
      local content = [[
---
key: value
...
]]
      local result = yaml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('key', result[1].key)
    end)

    it('should skip list items', function()
      local content = [[
items:
  - item1
  - item2
password: secret
]]
      local result = yaml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('password', result[1].key)
    end)

    it('should handle empty content', function()
      local content = ''
      local result = yaml_parser.parse(content)

      assert.equals(0, #result)
    end)

    it('should respect max_depth', function()
      require('camouflage.config').setup({
        parsers = {
          yaml = {
            max_depth = 1,
          },
          env = {
            include_commented = true,
          },
        },
      })

      local content = [[
level1:
  level2:
    secret: too_deep
top: visible
]]
      local result = yaml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = true
      end

      assert.is_true(keys['top'])
      assert.is_nil(keys['level1.level2.secret'])
    end)

    it('should parse literal block scalar (|)', function()
      local content = [[
certificate: |
  -----BEGIN CERTIFICATE-----
  MIIBkTCB+wIJAKHBfpE...
  -----END CERTIFICATE-----
other_key: value
]]
      local result = yaml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v
      end

      assert.is_not_nil(keys['certificate'])
      assert.is_true(keys['certificate'].is_multiline)
      assert.is_true(keys['certificate'].value:match('BEGIN CERTIFICATE') ~= nil)
      assert.equals('value', keys['other_key'].value)
    end)

    it('should parse folded block scalar (>)', function()
      local content = [[
description: >
  This is a long description
  that spans multiple lines
  and will be folded.
api_key: secret123
]]
      local result = yaml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v
      end

      assert.is_not_nil(keys['description'])
      assert.is_true(keys['description'].is_multiline)
      assert.equals('secret123', keys['api_key'].value)
    end)

    it('should handle block scalar with chomping indicators', function()
      local content = [[
keep_newlines: |+
  line1
  line2

strip_newlines: |-
  line1
  line2
next: value
]]
      local result = yaml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v
      end

      assert.is_not_nil(keys['keep_newlines'])
      assert.is_not_nil(keys['strip_newlines'])
      assert.equals('value', keys['next'].value)
    end)

    it('should handle nested multi-line values', function()
      local content = [[
database:
  credentials:
    private_key: |
      -----BEGIN RSA PRIVATE KEY-----
      MIIEpAIBAAKCAQEA...
      -----END RSA PRIVATE KEY-----
    password: secret123
]]
      local result = yaml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v
      end

      assert.is_not_nil(keys['database.credentials.private_key'])
      assert.is_true(keys['database.credentials.private_key'].is_multiline)
      assert.equals('secret123', keys['database.credentials.password'].value)
    end)
  end)
end)
