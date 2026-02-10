local styles = require('camouflage.styles')
local config = require('camouflage.config')

describe('camouflage.styles', function()
  before_each(function()
    config.setup()
  end)

  describe('generate_hidden_text', function()
    describe('stars style', function()
      it('should generate asterisks for given length', function()
        local result = styles.generate_hidden_text('stars', 10, 'secretpass')

        assert.equals('**********', result)
      end)

      it('should use mask_char from config', function()
        config.setup({ mask_char = '#' })

        local result = styles.generate_hidden_text('stars', 5, 'hello')

        assert.equals('#####', result)
      end)

      it('should respect mask_length from config', function()
        config.setup({ mask_length = 8 })

        local result = styles.generate_hidden_text('stars', 20, 'verylongpassword')

        assert.equals('********', result)
      end)
    end)

    describe('dotted style', function()
      it('should generate dots for given length', function()
        local result = styles.generate_hidden_text('dotted', 10, 'secretpass')

        assert.equals('••••••••••', result)
      end)

      it('should respect mask_length from config', function()
        config.setup({ mask_length = 5 })

        local result = styles.generate_hidden_text('dotted', 10, 'secretpass')

        assert.equals('•••••', result)
      end)
    end)

    describe('text style', function()
      it('should return hidden_text from config', function()
        local result = styles.generate_hidden_text('text', 10, 'secretpass')

        assert.equals('************************', result)
      end)

      it('should use custom hidden_text', function()
        config.setup({ hidden_text = '***MASKED***' })

        local result = styles.generate_hidden_text('text', 10, 'secretpass')

        assert.equals('***MASKED***', result)
      end)

      it('should ignore length parameter', function()
        local result1 = styles.generate_hidden_text('text', 5, 'short')
        local result2 = styles.generate_hidden_text('text', 100, 'verylongtext')

        assert.equals(result1, result2)
      end)
    end)

    describe('scramble style', function()
      it('should return scrambled text with same length', function()
        local original = 'secretpass'
        local result = styles.generate_hidden_text('scramble', #original, original)

        assert.equals(#original, #result)
      end)

      it('should preserve first and last character for long text', function()
        local original = 'secretpassword'
        local result = styles.generate_hidden_text('scramble', #original, original)

        assert.equals('s', result:sub(1, 1))
        assert.equals('d', result:sub(-1))
      end)

      it('should return asterisks for short text', function()
        local original = 'ab'
        local result = styles.generate_hidden_text('scramble', #original, original)

        assert.equals('**', result)
      end)

      it('should return asterisks when original_text is nil', function()
        local result = styles.generate_hidden_text('scramble', 5, nil)

        assert.equals('*****', result)
      end)
    end)

    describe('unknown style', function()
      it('should fallback to asterisks', function()
        local result = styles.generate_hidden_text('unknown', 5, 'hello')

        assert.equals('*****', result)
      end)
    end)
  end)

  describe('scramble_text', function()
    it('should return asterisks for single character', function()
      local result = styles.scramble_text('a')

      assert.equals('*', result)
    end)

    it('should return asterisks for two characters', function()
      local result = styles.scramble_text('ab')

      assert.equals('**', result)
    end)

    it('should preserve first and last character', function()
      local text = 'hello'
      local result = styles.scramble_text(text)

      assert.equals('h', result:sub(1, 1))
      assert.equals('o', result:sub(-1))
    end)

    it('should return same length', function()
      local text = 'mysecretpassword'
      local result = styles.scramble_text(text)

      assert.equals(#text, #result)
    end)

    it('should contain same characters', function()
      local text = 'abcd'
      local result = styles.scramble_text(text)

      -- Check all characters are present
      local chars = {}
      for i = 1, #text do
        chars[text:sub(i, i)] = (chars[text:sub(i, i)] or 0) + 1
      end

      for i = 1, #result do
        local c = result:sub(i, i)
        assert.is_true(chars[c] and chars[c] > 0)
        chars[c] = chars[c] - 1
      end
    end)
  end)

  describe('is_valid_style', function()
    it('should return true for stars', function()
      assert.is_true(styles.is_valid_style('stars'))
    end)

    it('should return true for dotted', function()
      assert.is_true(styles.is_valid_style('dotted'))
    end)

    it('should return true for text', function()
      assert.is_true(styles.is_valid_style('text'))
    end)

    it('should return true for scramble', function()
      assert.is_true(styles.is_valid_style('scramble'))
    end)

    it('should return false for invalid style', function()
      assert.is_false(styles.is_valid_style('invalid'))
    end)

    it('should return false for empty string', function()
      assert.is_false(styles.is_valid_style(''))
    end)

    it('should return false for nil', function()
      assert.is_false(styles.is_valid_style(nil))
    end)

    it('should be case sensitive', function()
      assert.is_false(styles.is_valid_style('STARS'))
      assert.is_false(styles.is_valid_style('Stars'))
    end)
  end)

  describe('get_available_styles', function()
    it('should return all four styles', function()
      local available = styles.get_available_styles()

      assert.equals(4, #available)
    end)

    it('should contain text style', function()
      local available = styles.get_available_styles()

      assert.is_true(vim.tbl_contains(available, 'text'))
    end)

    it('should contain dotted style', function()
      local available = styles.get_available_styles()

      assert.is_true(vim.tbl_contains(available, 'dotted'))
    end)

    it('should contain stars style', function()
      local available = styles.get_available_styles()

      assert.is_true(vim.tbl_contains(available, 'stars'))
    end)

    it('should contain scramble style', function()
      local available = styles.get_available_styles()

      assert.is_true(vim.tbl_contains(available, 'scramble'))
    end)
  end)

  describe('STYLES constants', function()
    it('should have TEXT constant', function()
      assert.equals('text', styles.STYLES.TEXT)
    end)

    it('should have DOTTED constant', function()
      assert.equals('dotted', styles.STYLES.DOTTED)
    end)

    it('should have STARS constant', function()
      assert.equals('stars', styles.STYLES.STARS)
    end)

    it('should have SCRAMBLE constant', function()
      assert.equals('scramble', styles.STYLES.SCRAMBLE)
    end)
  end)
end)
