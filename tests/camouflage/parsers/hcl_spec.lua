local hcl_parser = require('camouflage.parsers.hcl')

describe('camouflage.parsers.hcl', function()
  before_each(function()
    require('camouflage.config').setup({
      parsers = {
        hcl = { max_depth = 10 },
      },
    })
  end)

  describe('parse', function()
    -- Basic attribute tests
    it('should parse simple quoted string attribute', function()
      local content = 'api_key = "secret123"'
      local result = hcl_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('secret123', result[1].value)
    end)

    it('should parse unquoted number value', function()
      local content = 'port = 5432'
      local result = hcl_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('5432', result[1].value)
    end)

    it('should parse boolean values', function()
      local content = 'enabled = true'
      local result = hcl_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('true', result[1].value)
    end)

    it('should parse multiple attributes', function()
      local content = [[
username = "admin"
password = "secret"
port = 3306
]]
      local result = hcl_parser.parse(content)

      assert.equals(3, #result)
    end)

    -- Block tests
    it('should parse variable block default value', function()
      local content = [[
variable "db_password" {
  type    = string
  default = "secret123"
}
]]
      local result = hcl_parser.parse(content)

      -- Should find at least the default value
      local found = false
      for _, v in ipairs(result) do
        if v.value == 'secret123' then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('should parse resource attributes', function()
      local content = [[
resource "aws_db_instance" "main" {
  username = "admin"
  password = "secret"
}
]]
      local result = hcl_parser.parse(content)

      assert.is_true(#result >= 2)
    end)

    it('should parse provider credentials', function()
      local content = [[
provider "aws" {
  access_key = "AKIAIOSFODNN7EXAMPLE"
  secret_key = "wJalrXUtnFEMI"
}
]]
      local result = hcl_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('AKIAIOSFODNN7EXAMPLE', keys['access_key'])
    end)

    it('should parse locals block', function()
      local content = [[
locals {
  api_key = "sk-live-xxx"
}
]]
      local result = hcl_parser.parse(content)

      assert.equals(1, #result)
    end)

    -- Heredoc tests
    it('should parse heredoc strings', function()
      local content = [[
script = <<EOF
secret_value
EOF
]]
      local result = hcl_parser.parse(content)

      assert.equals(1, #result)
      assert.is_true(result[1].value:match('secret_value') ~= nil)
    end)

    it('should parse indented heredoc', function()
      local content = [[
script = <<-EOT
  indented content
EOT
]]
      local result = hcl_parser.parse(content)

      assert.equals(1, #result)
    end)

    -- Comment tests
    it('should handle hash comments', function()
      local content = [[
# This is a comment
api_key = "secret"
]]
      local result = hcl_parser.parse(content)

      assert.equals(1, #result)
    end)

    it('should handle inline comments', function()
      local content = 'api_key = "secret" # comment'
      local result = hcl_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('secret', result[1].value)
    end)

    -- Edge cases
    it('should handle empty content', function()
      local content = ''
      local result = hcl_parser.parse(content)

      assert.equals(0, #result)
    end)

    it('should skip variable references', function()
      local content = 'password = var.db_password'
      local result = hcl_parser.parse(content)

      assert.equals(0, #result)
    end)

    it('should skip function calls', function()
      local content = 'value = file("secret.txt")'
      local result = hcl_parser.parse(content)

      assert.equals(0, #result)
    end)

    -- Position accuracy
    it('should calculate correct byte positions', function()
      local content = 'key = "value"'
      local result = hcl_parser.parse(content)

      assert.equals(1, #result)
      -- "value" starts at position 7 (0-indexed: k=0,e=1,y=2, =3,space=4,"=5,v=6)
      assert.equals(7, result[1].start_index)
      assert.equals(12, result[1].end_index)
    end)
  end)
end)
