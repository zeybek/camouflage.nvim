local http_parser = require('camouflage.parsers.http')

describe('camouflage.parsers.http', function()
  describe('parse', function()
    it('should parse simple @variable = value', function()
      local content = '@api_key = sk-secret-123'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('sk-secret-123', result[1].value)
      assert.equals(0, result[1].line_number)
      assert.is_false(result[1].is_commented)
    end)

    it('should parse variable without spaces around =', function()
      local content = '@password=super-secret'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('password', result[1].key)
      assert.equals('super-secret', result[1].value)
    end)

    it('should parse variable with extra spaces', function()
      local content = '@token   =   my-token-value'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('token', result[1].key)
      assert.equals('my-token-value', result[1].value)
    end)

    it('should parse multiple variables', function()
      local content = [[
@api_key = key1
@secret = secret2
@base_url = https://api.example.com
]]
      local result = http_parser.parse(content)

      assert.equals(3, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('key1', result[1].value)
      assert.equals(0, result[1].line_number)

      assert.equals('secret', result[2].key)
      assert.equals('secret2', result[2].value)
      assert.equals(1, result[2].line_number)

      assert.equals('base_url', result[3].key)
      assert.equals('https://api.example.com', result[3].value)
      assert.equals(2, result[3].line_number)
    end)

    it('should handle variable names with dots', function()
      local content = '@db.password = mydbpass'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('db.password', result[1].key)
      assert.equals('mydbpass', result[1].value)
    end)

    it('should handle variable names with hyphens', function()
      local content = '@my-api-key = value123'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('my-api-key', result[1].key)
      assert.equals('value123', result[1].value)
    end)

    it('should handle variable names with $', function()
      local content = '@$env_var = prod'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('$env_var', result[1].key)
      assert.equals('prod', result[1].value)
    end)

    it('should handle values with variable references', function()
      local content = '@full_url = {{base_url}}/api/v1'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('full_url', result[1].key)
      assert.equals('{{base_url}}/api/v1', result[1].value)
    end)

    it('should skip comment lines', function()
      local content = [[
# This is a comment
@api_key = secret
// Another comment style
@password = pass123
]]
      local result = http_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('password', result[2].key)
    end)

    it('should skip request separators', function()
      local content = [[
@api_key = secret

### Get Users
GET {{base_url}}/users

### Create User
@new_var = value
]]
      local result = http_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('new_var', result[2].key)
    end)

    it('should skip lines without @', function()
      local content = [[
@api_key = secret
GET https://api.example.com
Authorization: Bearer {{api_key}}
@password = pass
]]
      local result = http_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('password', result[2].key)
    end)

    it('should handle empty file', function()
      local result = http_parser.parse('')
      assert.are.same({}, result)
    end)

    it('should skip empty values', function()
      -- Built via concat so the intentional trailing spaces on the last line do
      -- not show up as trailing whitespace inside a string literal (luacheck).
      local content = table.concat({
        '@empty =',
        '@valid = value',
        '@also_empty =' .. string.rep(' ', 3),
        '',
      }, '\n')
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('valid', result[1].key)
    end)

    it('should handle values with special characters', function()
      local content = '@password = p@ss$w0rd!#%^&*()'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('password', result[1].key)
      assert.equals('p@ss$w0rd!#%^&*()', result[1].value)
    end)

    it('should handle values with equals signs', function()
      local content = '@connection_string = host=localhost;user=admin;pass=secret'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('connection_string', result[1].key)
      assert.equals('host=localhost;user=admin;pass=secret', result[1].value)
    end)

    it('should handle leading whitespace on line', function()
      local content = '  @api_key = secret'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('secret', result[1].value)
    end)

    it('should calculate correct value positions', function()
      local content = '@key = value'
      local result = http_parser.parse(content)

      assert.equals(1, #result)
      -- @key = value
      -- 0123456789...
      -- value starts at index 7 (after "= ")
      assert.equals(7, result[1].start_index)
      assert.equals(12, result[1].end_index)
    end)
  end)

  describe('requests', function()
    local function parsed(lines)
      local content = table.concat(lines, '\n')
      local out = {}
      for _, v in ipairs(http_parser.parse(content)) do
        -- Every range points at the value itself.
        assert.equals(v.value, content:sub(v.start_index + 1, v.end_index))
        table.insert(out, v.key .. '=' .. v.value)
      end
      return out
    end

    it('masks the credential of an Authorization header, not its scheme', function()
      assert.same(
        { 'header.Authorization=http-bearer', 'header.Proxy-Authorization=dXNlcjpwYXNz' },
        parsed({
          'GET https://api.example.com/users',
          'Authorization: Bearer http-bearer',
          'Proxy-Authorization: Basic dXNlcjpwYXNz',
        })
      )
    end)

    it('masks sensitive headers and leaves the others alone', function()
      assert.same(
        { 'header.X-Api-Key=http-header', 'header.X-Auth-Token=auth-token' },
        parsed({
          'POST https://api.example.com/users',
          'X-Api-Key: http-header',
          'Content-Type: application/json',
          'Accept: */*',
          'X-Auth-Token: auth-token',
        })
      )
    end)

    it('keeps cookie names and masks their values', function()
      assert.same(
        { 'header.Cookie.session=http-cookie', 'header.Cookie.csrf=csrf-value' },
        parsed({ 'GET https://x.test/', 'Cookie: session=http-cookie; csrf=csrf-value' })
      )
    end)

    it('masks sensitive query parameters', function()
      assert.same(
        { 'query.api_key=http-query', 'query.access_token=query-token' },
        parsed({ 'GET https://x.test/users?api_key=http-query&page=3&access_token=query-token' })
      )
    end)

    it('masks a JSON body and a form body', function()
      assert.same(
        {
          'body.password=http-body',
          'body.name=John',
          'body.client_secret=form-secret',
        },
        parsed({
          'POST https://x.test/login',
          'Content-Type: application/json',
          '',
          '{"password": "http-body", "name": "John"}',
          '',
          '###',
          'POST https://x.test/charges',
          'Content-Type: application/x-www-form-urlencoded',
          '',
          'amount=2000&client_secret=form-secret&source=tok_visa',
        })
      )
    end)

    it('leaves {{variable}} references, comments and response scripts alone', function()
      assert.same(
        {},
        parsed({
          '# Authorization: Bearer not-a-header',
          'GET {{base_url}}/users?token={{token}}',
          'Authorization: Bearer {{api_key}}',
          'X-API-Secret: {{api_secret}}',
          '',
          '{"password": "{{db.password}}"}',
          '',
          '> {% client.global.set("token", response.body.token); %}',
        })
      )
    end)

    it('reads a request line that is only a URL', function()
      assert.same(
        { 'header.Authorization=bare-url' },
        parsed({ 'https://x.test/users', 'Authorization: Bearer bare-url' })
      )
    end)

    it('reads requests on the tree-sitter path too', function()
      local lines = { '@token = ts-var', 'GET https://x.test/', 'Authorization: Bearer ts-header' }
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].filetype = 'http'

      local keys = {}
      for _, v in ipairs(http_parser.parse(table.concat(lines, '\n'), bufnr)) do
        table.insert(keys, v.key .. '=' .. v.value)
      end
      vim.api.nvim_buf_delete(bufnr, { force = true })

      assert.same({ 'token=ts-var', 'header.Authorization=ts-header' }, keys)
    end)

    it('keeps the variables and puts everything in file order', function()
      assert.same(
        { 'token=http-var', 'header.Authorization=after-var' },
        parsed({ '@token = http-var', 'GET https://x.test/', 'Authorization: Bearer after-var' })
      )
    end)
  end)
end)
