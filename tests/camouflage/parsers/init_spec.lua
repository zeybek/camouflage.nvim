local parsers = require('camouflage.parsers')
local config = require('camouflage.config')

describe('camouflage.parsers', function()
  before_each(function()
    config.setup()
    parsers.setup()
  end)

  describe('match_pattern', function()
    describe('prefix patterns (.env*)', function()
      it('should match .env.local with .env*', function()
        assert.is_true(parsers.match_pattern('.env.local', '.env*'))
      end)

      it('should match .env with .env*', function()
        assert.is_true(parsers.match_pattern('.env', '.env*'))
      end)

      it('should match .env.production with .env*', function()
        assert.is_true(parsers.match_pattern('.env.production', '.env*'))
      end)

      it('should not match env.local with .env*', function()
        assert.is_false(parsers.match_pattern('env.local', '.env*'))
      end)
    end)

    describe('suffix patterns (*.json)', function()
      it('should match config.json with *.json', function()
        assert.is_true(parsers.match_pattern('config.json', '*.json'))
      end)

      it('should match settings.json with *.json', function()
        assert.is_true(parsers.match_pattern('settings.json', '*.json'))
      end)

      it('should not match test.txt with *.json', function()
        assert.is_false(parsers.match_pattern('test.txt', '*.json'))
      end)

      it('should not match json.backup with *.json', function()
        assert.is_false(parsers.match_pattern('json.backup', '*.json'))
      end)
    end)

    describe('exact patterns', function()
      it('should match .envrc with .envrc', function()
        assert.is_true(parsers.match_pattern('.envrc', '.envrc'))
      end)

      it('should not match .envrc.bak with .envrc', function()
        assert.is_false(parsers.match_pattern('.envrc.bak', '.envrc'))
      end)
    end)

    describe('extension patterns (*rc)', function()
      it('should match .bashrc with *rc', function()
        assert.is_true(parsers.match_pattern('.bashrc', '*rc'))
      end)

      it('should match .zshrc with *rc', function()
        assert.is_true(parsers.match_pattern('.zshrc', '*rc'))
      end)
    end)

    describe('yaml patterns', function()
      it('should match config.yaml with *.yaml', function()
        assert.is_true(parsers.match_pattern('config.yaml', '*.yaml'))
      end)

      it('should match config.yml with *.yml', function()
        assert.is_true(parsers.match_pattern('config.yml', '*.yml'))
      end)
    end)
  end)

  describe('find_parser_for_file', function()
    it('should return env parser for test.env', function()
      local parser, name = parsers.find_parser_for_file('test.env')

      assert.is_not_nil(parser)
      assert.equals('env', name)
    end)

    it('should return env parser for .env.local', function()
      local parser, name = parsers.find_parser_for_file('.env.local')

      assert.is_not_nil(parser)
      assert.equals('env', name)
    end)

    it('should return json parser for config.json', function()
      local parser, name = parsers.find_parser_for_file('config.json')

      assert.is_not_nil(parser)
      assert.equals('json', name)
    end)

    it('should return yaml parser for config.yaml', function()
      local parser, name = parsers.find_parser_for_file('config.yaml')

      assert.is_not_nil(parser)
      assert.equals('yaml', name)
    end)

    it('should return yaml parser for config.yml', function()
      local parser, name = parsers.find_parser_for_file('config.yml')

      assert.is_not_nil(parser)
      assert.equals('yaml', name)
    end)

    it('should exclude .camouflage.yaml from parsing', function()
      local parser, name = parsers.find_parser_for_file('.camouflage.yaml')

      assert.is_nil(parser)
      assert.is_nil(name)
    end)

    it('should exclude project config file with custom filename', function()
      local config = require('camouflage.config')
      config.setup({ project_config = { filename = '.my-camouflage.yml' } })
      parsers.clear_cache()

      local parser, name = parsers.find_parser_for_file('.my-camouflage.yml')

      assert.is_nil(parser)
      assert.is_nil(name)
    end)

    it('should return toml parser for config.toml', function()
      local parser, name = parsers.find_parser_for_file('config.toml')

      assert.is_not_nil(parser)
      assert.equals('toml', name)
    end)

    it('should return properties parser for app.properties', function()
      local parser, name = parsers.find_parser_for_file('app.properties')

      assert.is_not_nil(parser)
      assert.equals('properties', name)
    end)

    it('should return nil for unknown.xyz', function()
      local parser, name = parsers.find_parser_for_file('unknown.xyz')

      assert.is_nil(parser)
      assert.is_nil(name)
    end)

    it('should return nil for unsupported extensions', function()
      local parser, name = parsers.find_parser_for_file('readme.md')

      assert.is_nil(parser)
      assert.is_nil(name)
    end)

    it('should handle full paths', function()
      local parser, name = parsers.find_parser_for_file('/home/user/project/.env')

      assert.is_not_nil(parser)
      assert.equals('env', name)
    end)
  end)

  describe('is_supported', function()
    it('should return true for test.env', function()
      assert.is_true(parsers.is_supported('test.env'))
    end)

    it('should return true for .env', function()
      assert.is_true(parsers.is_supported('.env'))
    end)

    it('should return true for config.json', function()
      assert.is_true(parsers.is_supported('config.json'))
    end)

    it('should return true for settings.yaml', function()
      assert.is_true(parsers.is_supported('settings.yaml'))
    end)

    it('should return true for config.toml', function()
      assert.is_true(parsers.is_supported('config.toml'))
    end)

    it('should return true for app.properties', function()
      assert.is_true(parsers.is_supported('app.properties'))
    end)

    it('should return false for unknown.xyz', function()
      assert.is_false(parsers.is_supported('unknown.xyz'))
    end)

    it('should return false for unsupported file', function()
      assert.is_false(parsers.is_supported('script.py'))
    end)

    it('should handle full paths', function()
      assert.is_true(parsers.is_supported('/path/to/.env.production'))
    end)
  end)

  describe('register', function()
    it('should register a new parser', function()
      local custom_parser = {
        parse = function()
          return {}
        end,
        can_parse = function()
          return true
        end,
      }

      parsers.register('custom', custom_parser)

      assert.equals(custom_parser, parsers.get('custom'))
    end)
  end)

  describe('get', function()
    it('should return registered parser', function()
      local env_parser = parsers.get('env')

      assert.is_not_nil(env_parser)
      assert.is_function(env_parser.parse)
    end)

    it('should return nil for unregistered parser', function()
      local parser = parsers.get('nonexistent')

      assert.is_nil(parser)
    end)
  end)

  describe('parse', function()
    it('should parse env content', function()
      local content = 'API_KEY=secret123'
      local result = parsers.parse('test.env', content)

      assert.equals(1, #result)
      assert.equals('API_KEY', result[1].key)
    end)

    it('should return empty table for unsupported file', function()
      local result = parsers.parse('unknown.xyz', 'content')

      assert.is_table(result)
      assert.equals(0, #result)
    end)

    it('should handle parser errors gracefully', function()
      -- Register a parser that throws
      parsers.register('broken', {
        parse = function()
          error('Parser error')
        end,
      })

      -- Temporarily add pattern for broken parser
      local patterns = config.get().patterns
      table.insert(patterns, 1, { file_pattern = '*.broken', parser = 'broken' })

      local result = parsers.parse('test.broken', 'content')

      assert.is_table(result)
      assert.equals(0, #result)
    end)
  end)

  describe('setup', function()
    it('should register all default parsers', function()
      parsers.parsers = {}
      parsers.setup()

      assert.is_not_nil(parsers.get('env'))
      assert.is_not_nil(parsers.get('json'))
      assert.is_not_nil(parsers.get('yaml'))
      assert.is_not_nil(parsers.get('toml'))
      assert.is_not_nil(parsers.get('properties'))
    end)
  end)
end)
