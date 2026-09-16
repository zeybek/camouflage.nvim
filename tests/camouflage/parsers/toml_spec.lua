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

    it('masks a basic string containing an escaped quote in full', function()
      local content = 'pwd = "ab\\"cd"'
      local result = toml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('pwd', result[1].key)
      -- The escaped quote no longer terminates the string early.
      assert.equals('ab\\"cd', result[1].value)
      assert.equals('ab\\"cd', content:sub(result[1].start_index + 1, result[1].end_index))
    end)
  end)

  describe('arrays', function()
    local function values(content)
      local result = toml_parser.parse(content)
      for _, v in ipairs(result) do
        assert.equals(v.value, content:sub(v.start_index + 1, v.end_index))
      end
      return result
    end

    it('reports each item of a single-line array', function()
      local result = values('keys = ["one", \'two\', 3, true]')

      assert.equals(4, #result)
      for i, expected in ipairs({ 'one', 'two', '3', 'true' }) do
        assert.equals('keys', result[i].key)
        assert.equals(expected, result[i].value)
      end
    end)

    it('reports each item of a multi-line array and keeps parsing after it', function()
      local content = table.concat({
        '[api]',
        'keys = [',
        '  "multi-one", # first',
        '  "multi-two",',
        ']',
        'token = "after"',
      }, '\n')
      local result = values(content)

      assert.equals(3, #result)
      assert.equals('api.keys', result[1].key)
      assert.equals('multi-one', result[1].value)
      assert.equals(2, result[1].line_number)
      assert.equals('multi-two', result[2].value)
      assert.equals(3, result[2].line_number)
      assert.equals('api.token', result[3].key)
    end)

    it('skips nested arrays and inline tables', function()
      local result = values('mixed = [["nested"], { a = "table" }, "kept"]')

      assert.equals(1, #result)
      assert.equals('kept', result[1].value)
    end)
  end)

  describe('quoted keys and multi-line strings', function()
    local function parse(lines)
      local content = table.concat(lines, '\n')
      local result = toml_parser.parse(content)
      for _, v in ipairs(result) do
        assert.equals(v.value, content:sub(v.start_index + 1, v.end_index))
      end
      return result, content
    end

    it('finds the value of a quoted key that contains =', function()
      local result, content = parse({ '"a=b" = "quoted-key-secret"', "'x=y' = 'literal-key'" })

      assert.equals(2, #result)
      assert.equals('a=b', result[1].key)
      assert.equals(#'"a=b" = "', result[1].start_index)
      assert.equals('x=y', result[2].key)
      assert.equals(content:find('literal-key', 1, true) - 1, result[2].start_index)
    end)

    it('masks a multi-line basic string and trims the newline after the opener', function()
      local result =
        parse({ '[server]', 'cert = """', 'multi-one', 'multi-two"""', 'next = "after"' })

      assert.equals(2, #result)
      assert.equals('server.cert', result[1].key)
      assert.equals('multi-one\nmulti-two', result[1].value)
      assert.equals(2, result[1].line_number)
      assert.is_true(result[1].is_multiline)
      assert.equals('server.next', result[2].key)
    end)

    it('masks a multi-line literal string that starts on the key line', function()
      local result = parse({ "raw = '''first-part", "second-part'''" })

      assert.equals(1, #result)
      assert.equals('first-part\nsecond-part', result[1].value)
    end)

    it('does not end a basic string at an escaped quote', function()
      local result = parse({ 'esc = """a \\""" still', 'end"""' })

      assert.equals(1, #result)
      assert.equals('a \\""" still\nend', result[1].value)
    end)

    it('keeps single-line triple-quoted strings on the single-line path', function()
      local result = parse({ 'single = """one line"""' })

      assert.equals(1, #result)
      assert.equals('one line', result[1].value)
      assert.is_nil(result[1].is_multiline)
    end)
  end)
end)
