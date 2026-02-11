local custom = require('camouflage.parsers.custom')
local config = require('camouflage.config')
local parsers = require('camouflage.parsers')

describe('camouflage.parsers.custom', function()
  before_each(function()
    config.setup({
      custom_patterns = {},
    })
    parsers.setup()
  end)

  describe('parse', function()
    it('should parse key + value pattern', function()
      local pattern_config = {
        file_pattern = { '*.myconfig' },
        pattern = '@([%w_]+)%s*=%s*(.+)',
        key_capture = 1,
        value_capture = 2,
      }
      local content = '@api_key = secret123'
      local result = custom.parse(content, pattern_config)

      assert.equals(1, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('secret123', result[1].value)
      assert.equals(0, result[1].line_number)
      assert.is_false(result[1].is_nested)
      assert.is_false(result[1].is_commented)
    end)

    it('should parse value only pattern (key optional)', function()
      local pattern_config = {
        file_pattern = { '*.secret' },
        pattern = 'SECRET:%s*(.+)',
        value_capture = 1,
      }
      local content = 'SECRET: my_secret_value'
      local result = custom.parse(content, pattern_config)

      assert.equals(1, #result)
      assert.equals('custom_1', result[1].key)
      assert.equals('my_secret_value', result[1].value)
    end)

    it('should parse multiple matches on same line', function()
      local pattern_config = {
        file_pattern = { '*.conf' },
        pattern = '%$(%w+)=([^%s]+)',
        key_capture = 1,
        value_capture = 2,
      }
      local content = '$USER=admin $PASS=secret123'
      local result = custom.parse(content, pattern_config)

      assert.equals(2, #result)
      assert.equals('USER', result[1].key)
      assert.equals('admin', result[1].value)
      assert.equals('PASS', result[2].key)
      assert.equals('secret123', result[2].value)
    end)

    it('should parse multiple lines', function()
      local pattern_config = {
        file_pattern = { '*.cfg' },
        pattern = '(%w+)%s*::%s*(.+)',
        key_capture = 1,
        value_capture = 2,
      }
      local content = [[
username :: admin
password :: supersecret
token :: abc123xyz
]]
      local result = custom.parse(content, pattern_config)

      assert.equals(3, #result)
      assert.equals('username', result[1].key)
      assert.equals('admin', result[1].value)
      assert.equals(0, result[1].line_number)

      assert.equals('password', result[2].key)
      assert.equals('supersecret', result[2].value)
      assert.equals(1, result[2].line_number)

      assert.equals('token', result[3].key)
      assert.equals('abc123xyz', result[3].value)
      assert.equals(2, result[3].line_number)
    end)

    it('should return empty array for empty file', function()
      local pattern_config = {
        file_pattern = { '*.test' },
        pattern = '(%w+)=(.+)',
        key_capture = 1,
        value_capture = 2,
      }
      local result = custom.parse('', pattern_config)

      assert.is_table(result)
      assert.equals(0, #result)
    end)

    it('should return empty array when pattern does not match', function()
      local pattern_config = {
        file_pattern = { '*.test' },
        pattern = '@(%w+)=(.+)',
        key_capture = 1,
        value_capture = 2,
      }
      local content = 'no match here'
      local result = custom.parse(content, pattern_config)

      assert.is_table(result)
      assert.equals(0, #result)
    end)

    it('should calculate correct byte positions', function()
      local pattern_config = {
        file_pattern = { '*.test' },
        pattern = '(%w+)=(.+)',
        key_capture = 1,
        value_capture = 2,
      }
      local content = 'KEY=value'
      local result = custom.parse(content, pattern_config)

      assert.equals(1, #result)
      -- "value" starts at position 4 (0-indexed: K=0, E=1, Y=2, ==3, v=4)
      assert.equals(4, result[1].start_index)
      assert.equals(9, result[1].end_index)
    end)

    it('should handle patterns with no key capture', function()
      local pattern_config = {
        file_pattern = { '*.test' },
        pattern = 'password:%s*(.+)',
        value_capture = 1,
      }
      local content = [[
password: first_pass
password: second_pass
]]
      local result = custom.parse(content, pattern_config)

      assert.equals(2, #result)
      assert.equals('custom_1', result[1].key)
      assert.equals('first_pass', result[1].value)
      assert.equals('custom_2', result[2].key)
      assert.equals('second_pass', result[2].value)
    end)

    it('should skip matches with empty values', function()
      local pattern_config = {
        file_pattern = { '*.test' },
        pattern = '(%w+)=(.*)',
        key_capture = 1,
        value_capture = 2,
      }
      local content = [[
KEY1=value1
KEY2=
KEY3=value3
]]
      local result = custom.parse(content, pattern_config)

      assert.equals(2, #result)
      assert.equals('KEY1', result[1].key)
      assert.equals('KEY3', result[2].key)
    end)
  end)

  describe('find_matching_pattern', function()
    it('should return matching pattern config for file', function()
      config.setup({
        custom_patterns = {
          {
            file_pattern = { '*.myconfig' },
            pattern = '@([%w_]+)%s*=%s*(.+)',
            key_capture = 1,
            value_capture = 2,
          },
        },
      })

      local pattern_config = custom.find_matching_pattern('test.myconfig')

      assert.is_not_nil(pattern_config)
      assert.equals('@([%w_]+)%s*=%s*(.+)', pattern_config.pattern)
      assert.equals(1, pattern_config.key_capture)
      assert.equals(2, pattern_config.value_capture)
    end)

    it('should return nil when no pattern matches', function()
      config.setup({
        custom_patterns = {
          {
            file_pattern = { '*.myconfig' },
            pattern = '@([%w_]+)%s*=%s*(.+)',
            key_capture = 1,
            value_capture = 2,
          },
        },
      })

      local pattern_config = custom.find_matching_pattern('test.other')

      assert.is_nil(pattern_config)
    end)

    it('should handle file_pattern as string', function()
      config.setup({
        custom_patterns = {
          {
            file_pattern = '*.myconfig',
            pattern = '@([%w_]+)%s*=%s*(.+)',
            key_capture = 1,
            value_capture = 2,
          },
        },
      })

      local pattern_config = custom.find_matching_pattern('test.myconfig')

      assert.is_not_nil(pattern_config)
    end)

    it('should handle file_pattern as table', function()
      config.setup({
        custom_patterns = {
          {
            file_pattern = { '*.myconfig', '*.myconf' },
            pattern = '@([%w_]+)%s*=%s*(.+)',
            key_capture = 1,
            value_capture = 2,
          },
        },
      })

      local pattern_config1 = custom.find_matching_pattern('test.myconfig')
      local pattern_config2 = custom.find_matching_pattern('test.myconf')

      assert.is_not_nil(pattern_config1)
      assert.is_not_nil(pattern_config2)
    end)

    it('should return nil when custom_patterns is empty', function()
      config.setup({
        custom_patterns = {},
      })

      local pattern_config = custom.find_matching_pattern('test.myconfig')

      assert.is_nil(pattern_config)
    end)

    it('should return first matching pattern when multiple match', function()
      config.setup({
        custom_patterns = {
          {
            file_pattern = { '*.myconfig' },
            pattern = 'first_pattern',
            value_capture = 1,
          },
          {
            file_pattern = { '*.myconfig' },
            pattern = 'second_pattern',
            value_capture = 1,
          },
        },
      })

      local pattern_config = custom.find_matching_pattern('test.myconfig')

      assert.is_not_nil(pattern_config)
      assert.equals('first_pattern', pattern_config.pattern)
    end)
  end)

  describe('integration with parsers module', function()
    it('should use custom parser when no built-in parser matches', function()
      config.setup({
        custom_patterns = {
          {
            file_pattern = { '*.myconfig' },
            pattern = '@([%w_]+)%s*=%s*(.+)',
            key_capture = 1,
            value_capture = 2,
          },
        },
      })
      parsers.setup()

      local parser, name = parsers.find_parser_for_file('test.myconfig')

      assert.is_not_nil(parser)
      assert.equals('custom', name)
    end)

    it('should prefer built-in parser over custom pattern', function()
      config.setup({
        custom_patterns = {
          {
            file_pattern = { '*.json' },
            pattern = 'custom_pattern',
            value_capture = 1,
          },
        },
      })
      parsers.setup()

      local parser, name = parsers.find_parser_for_file('test.json')

      assert.is_not_nil(parser)
      assert.equals('json', name)
    end)

    it('should parse content using custom parser via parsers.parse', function()
      config.setup({
        custom_patterns = {
          {
            file_pattern = { '*.myconfig' },
            pattern = '@([%w_]+)%s*=%s*(.+)',
            key_capture = 1,
            value_capture = 2,
          },
        },
      })
      parsers.setup()

      local content = '@api_key = secret123'
      local result = parsers.parse('test.myconfig', content)

      assert.equals(1, #result)
      assert.equals('api_key', result[1].key)
      assert.equals('secret123', result[1].value)
    end)

    it('should return empty array for file with no matching pattern', function()
      config.setup({
        custom_patterns = {},
      })
      parsers.setup()

      local result = parsers.parse('test.unknown', 'some content')

      assert.is_table(result)
      assert.equals(0, #result)
    end)
  end)
end)
