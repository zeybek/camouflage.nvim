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

  describe('java properties files', function()
    local function by_key(lines, filename)
      local content = table.concat(lines, '\n')
      local keys = {}
      for _, v in ipairs(properties_parser.parse(content, nil, filename or 'app.properties')) do
        keys[v.key] = v
      end
      return keys, content
    end

    it('accepts whitespace as the separator', function()
      local keys, content = by_key({ 'db.password   space-separated-secret' })

      local var = keys['db.password']
      assert.equals('space-separated-secret', var.value)
      assert.equals(var.value, content:sub(var.start_index + 1, var.end_index))
    end)

    it('accepts brackets and escaped separators in keys', function()
      local keys = by_key({ 'spring.ds[0].password=bracket-key-secret', 'k\\:x\\=y = escaped-key' })

      assert.equals('bracket-key-secret', keys['spring.ds[0].password'].value)
      assert.equals('escaped-key', keys['k:x=y'].value)
    end)

    it('joins continuation lines into one masked value', function()
      local keys, content = by_key({
        'db.pw=first\\',
        '    continued\\',
        '    last',
        'after=done',
      })

      local var = keys['db.pw']
      assert.equals('firstcontinuedlast', var.value)
      assert.is_true(var.is_multiline)
      assert.equals(#'db.pw=', var.start_index)
      assert.equals(content:find('last', 1, true) + #'last' - 1, var.end_index)
      assert.equals('done', keys.after.value)
    end)

    it('does not continue a value that ends with an escaped backslash', function()
      local keys = by_key({ 'path=C:\\\\', 'next=value' })

      assert.equals('C:\\\\', keys.path.value)
      assert.is_nil(keys.path.is_multiline)
      assert.equals('value', keys.next.value)
    end)

    it('keeps the stricter rules for .ini and .conf files', function()
      local keys = by_key({ 'listen 80;', 'db.pw=first\\', 'next=value' }, 'nginx.conf')

      assert.is_nil(keys.listen)
      assert.equals('first\\', keys['db.pw'].value)
      assert.equals('value', keys.next.value)
    end)

    it('uses the buffer name when no filename is passed', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '/buffer.properties')

      local result = properties_parser.parse('db.password buffer-secret', bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })

      assert.equals(1, #result)
      assert.equals('buffer-secret', result[1].value)
    end)

    it('gets the filename through the parser registry', function()
      require('camouflage.parsers').setup()

      local result = require('camouflage.parsers').parse(
        '/tmp/registry.properties',
        'db.password registry-secret'
      )

      assert.equals(1, #result)
      assert.equals('registry-secret', result[1].value)
    end)
  end)
end)
