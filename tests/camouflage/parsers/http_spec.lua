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
      local content = [[
@empty =
@valid = value
@also_empty =   
]]
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
end)
