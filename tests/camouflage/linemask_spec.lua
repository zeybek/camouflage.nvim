local linemask = require('camouflage.linemask')
local config = require('camouflage.config')

describe('camouflage.linemask', function()
  before_each(function()
    config.setup({ style = 'stars', mask_char = '*' })
  end)

  describe('find_value', function()
    local cases = {
      { 'API_KEY=secret-value', 8, 'secret-value' },
      { 'export API_KEY="secret-value"', 16, 'secret-value' },
      { '# API_KEY=secret-value', 10, 'secret-value' },
      { '  "token": "secret-value",', 12, 'secret-value' },
      { '- password: secret-value', 12, 'secret-value' },
      { "  'token': 'secret-value'", 12, 'secret-value' },
      { 'ENV API_TOKEN secret-value', 14, 'secret-value' },
      { 'ARG API_TOKEN=secret-value', 14, 'secret-value' },
      { '  <password>secret-value</password>', 12, 'secret-value' },
      { 'key = "secret-value"', 7, 'secret-value' },
    }

    for _, case in ipairs(cases) do
      local line, col, value = case[1], case[2], case[3]
      it(('finds the value in %q'):format(line), function()
        local got_col, got_value = linemask.find_value(line)
        assert.equals(col, got_col)
        assert.equals(value, got_value)
      end)
    end

    it('leaves lines without a value alone', function()
      local lines = {
        '',
        '# a comment',
        '{',
        'local value = 42',
        'KEY=',
        'key:',
        '[section]',
      }
      for _, line in ipairs(lines) do
        local col = linemask.find_value(line)
        assert.is_nil(col, ('%q should not look like a value'):format(line))
      end
    end)
  end)

  describe('mask_line', function()
    it('replaces the value and keeps everything around it', function()
      assert.equals(
        'API_KEY=************',
        linemask.mask_line('API_KEY=secret-value', config.get())
      )
    end)

    it('keeps the quotes, comma and closing tag', function()
      assert.equals(
        '  "token": "************",',
        linemask.mask_line('  "token": "secret-value",', config.get())
      )
      assert.equals(
        '  <password>************</password>',
        linemask.mask_line('  <password>secret-value</password>', config.get())
      )
    end)

    it('masks by display width, not byte length', function()
      local masked = linemask.mask_line('NOTE=şifre', config.get())
      assert.equals('NOTE=*****', masked)
    end)

    it('follows the configured style', function()
      config.setup({ style = 'dotted' })
      assert.equals('KEY=••••••', linemask.mask_line('KEY=secret', config.get()))
    end)

    it('returns nil when there is nothing to mask', function()
      assert.is_nil(linemask.mask_line('local value = nil', config.get()))
    end)
  end)
end)
