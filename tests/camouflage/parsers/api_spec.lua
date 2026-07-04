local camouflage = require('camouflage')
local parsers = require('camouflage.parsers')
local config = require('camouflage.config')
local state = require('camouflage.state')

describe('camouflage parser public API', function()
  local function count_bufenter_pattern(pattern)
    local count = 0
    for _, autocmd in
      ipairs(vim.api.nvim_get_autocmds({
        group = state.augroup,
        event = 'BufEnter',
      }))
    do
      if autocmd.pattern == pattern then
        count = count + 1
      end
    end
    return count
  end

  before_each(function()
    config.setup()
    parsers.setup()
    require('camouflage.autocmds').setup()
  end)

  describe('register_parser', function()
    it('registers a parser with metadata and resolves by file_patterns', function()
      camouflage.register_parser({
        name = 'kdl',
        file_patterns = { '*.kdl' },
        parser = {
          parse = function()
            return {
              {
                key = 'k',
                value = 'v',
                start_index = 0,
                end_index = 1,
                line_number = 0,
                is_nested = false,
                is_commented = false,
              },
            }
          end,
        },
      })

      local parser, name = parsers.find_parser_for_file('app.kdl')
      assert.is_not_nil(parser)
      assert.equals('kdl', name)
    end)

    it('refreshes automatic masking patterns after setup', function()
      assert.equals(0, count_bufenter_pattern('*.kdl'))

      camouflage.register_parser({
        name = 'kdl',
        file_patterns = { '*.kdl' },
        parser = {
          parse = function()
            return {}
          end,
        },
      })

      assert.is_true(count_bufenter_pattern('*.kdl') > 0)

      local first_count = count_bufenter_pattern('*.kdl')
      camouflage.register_parser({
        name = 'kdl',
        file_patterns = { '*.kdl' },
        parser = {
          parse = function()
            return {}
          end,
        },
      })

      assert.equals(first_count, count_bufenter_pattern('*.kdl'))
    end)

    it('higher priority wins on conflict', function()
      camouflage.register_parser({
        name = 'low',
        file_patterns = { '*.dup' },
        priority = 10,
        parser = {
          parse = function()
            return {}
          end,
        },
      })
      camouflage.register_parser({
        name = 'high',
        file_patterns = { '*.dup' },
        priority = 100,
        parser = {
          parse = function()
            return {}
          end,
        },
      })

      local _, name = parsers.find_parser_for_file('x.dup')
      assert.equals('high', name)
    end)

    it('config.patterns takes precedence over entry resolution', function()
      -- builtin json parser is matched via config.patterns first
      local _, name = parsers.find_parser_for_file('config.json')
      assert.equals('json', name)
    end)
  end)

  describe('register_pattern', function()
    it('registers a Lua-pattern based parser', function()
      camouflage.register_pattern({
        name = 'token_lines',
        file_patterns = { '*.tok' },
        pattern = '^(%w+)=(%S+)$',
        key_capture = 1,
        value_capture = 2,
      })

      local content = 'TOKEN=abc123'
      local result = parsers.parse('foo.tok', content)
      assert.is_table(result)
      assert.equals(1, #result)
      assert.equals('abc123', result[1].value)
    end)

    it('refreshes automatic masking patterns after setup', function()
      assert.equals(0, count_bufenter_pattern('*.tok'))

      camouflage.register_pattern({
        name = 'token_lines',
        file_patterns = { '*.tok' },
        pattern = '^(%w+)=(%S+)$',
        key_capture = 1,
        value_capture = 2,
      })

      assert.is_true(count_bufenter_pattern('*.tok') > 0)
    end)
  end)

  describe('unregister_parser', function()
    it('removes a registered parser', function()
      camouflage.register_parser({
        name = 'tmp',
        file_patterns = { '*.tmp' },
        parser = {
          parse = function()
            return {}
          end,
        },
      })
      assert.is_not_nil(parsers.get('tmp'))

      camouflage.unregister_parser('tmp')
      assert.is_nil(parsers.get('tmp'))
    end)

    it('refreshes automatic masking patterns after removing a user parser', function()
      camouflage.register_parser({
        name = 'tmp',
        file_patterns = { '*.tmp' },
        parser = {
          parse = function()
            return {}
          end,
        },
      })
      assert.is_true(count_bufenter_pattern('*.tmp') > 0)

      camouflage.unregister_parser('tmp')

      assert.equals(0, count_bufenter_pattern('*.tmp'))
    end)

    it('can remove a builtin parser', function()
      assert.is_not_nil(parsers.get('json'))
      camouflage.unregister_parser('json')
      assert.is_nil(parsers.get('json'))
    end)
  end)

  describe('list_parsers', function()
    it('returns all registered parsers sorted by priority desc', function()
      camouflage.register_parser({
        name = 'top',
        file_patterns = { '*.top' },
        priority = 999,
        parser = {
          parse = function()
            return {}
          end,
        },
      })

      local list = camouflage.list_parsers()
      assert.is_true(#list > 0)
      assert.equals('top', list[1].name)
    end)

    it('marks builtin source', function()
      local list = camouflage.list_parsers()
      local found_builtin = false
      for _, e in ipairs(list) do
        if e.source == 'builtin' then
          found_builtin = true
          break
        end
      end
      assert.is_true(found_builtin)
    end)
  end)

  describe('get_parser', function()
    it('returns nil for unknown parser', function()
      assert.is_nil(camouflage.get_parser('nonexistent'))
    end)
    it('returns registered parser', function()
      assert.is_not_nil(camouflage.get_parser('env'))
    end)
  end)
end)
