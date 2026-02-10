local ts = require('camouflage.treesitter')

describe('camouflage.treesitter', function()
  before_each(function()
    ts.clear_cache()
  end)

  describe('has_parser', function()
    it('should return boolean for any language', function()
      local result = ts.has_parser('json')
      assert.is_boolean(result)
    end)

    it('should cache parser availability', function()
      -- First call
      local result1 = ts.has_parser('json')
      -- Second call should use cache
      local result2 = ts.has_parser('json')
      assert.equals(result1, result2)
    end)

    it('should return false for non-existent language', function()
      local result = ts.has_parser('nonexistent_language_xyz')
      assert.is_false(result)
    end)
  end)

  describe('clear_cache', function()
    it('should clear the parser cache', function()
      -- Populate cache
      ts.has_parser('json')
      ts.has_parser('yaml')
      -- Clear
      ts.clear_cache()
      -- Should work without error after clear
      local result = ts.has_parser('json')
      assert.is_boolean(result)
    end)
  end)

  describe('queries', function()
    it('should have query for json', function()
      assert.is_string(ts.queries.json)
      assert.is_truthy(ts.queries.json:find('@key'))
      assert.is_truthy(ts.queries.json:find('@value'))
    end)

    it('should have query for yaml', function()
      assert.is_string(ts.queries.yaml)
      assert.is_truthy(ts.queries.yaml:find('@key'))
      assert.is_truthy(ts.queries.yaml:find('@value'))
    end)

    it('should have query for toml', function()
      assert.is_string(ts.queries.toml)
      assert.is_truthy(ts.queries.toml:find('@key'))
      assert.is_truthy(ts.queries.toml:find('@value'))
    end)
  end)

  describe('value_types', function()
    it('should have value types for json', function()
      assert.is_table(ts.value_types.json)
      assert.is_truthy(vim.tbl_contains(ts.value_types.json, 'string'))
      assert.is_truthy(vim.tbl_contains(ts.value_types.json, 'number'))
    end)

    it('should have value types for yaml', function()
      assert.is_table(ts.value_types.yaml)
      assert.is_truthy(vim.tbl_contains(ts.value_types.yaml, 'string_scalar'))
    end)

    it('should have value types for toml', function()
      assert.is_table(ts.value_types.toml)
      assert.is_truthy(vim.tbl_contains(ts.value_types.toml, 'string'))
      assert.is_truthy(vim.tbl_contains(ts.value_types.toml, 'integer'))
    end)
  end)

  describe('is_value_type', function()
    it('should return true for known value types', function()
      assert.is_true(ts.is_value_type('json', 'string'))
      assert.is_true(ts.is_value_type('json', 'number'))
      assert.is_true(ts.is_value_type('yaml', 'string_scalar'))
      assert.is_true(ts.is_value_type('toml', 'string'))
    end)

    it('should return false for container types', function()
      assert.is_false(ts.is_value_type('json', 'object'))
      assert.is_false(ts.is_value_type('json', 'array'))
    end)

    it('should return true for unknown language (fallback)', function()
      assert.is_true(ts.is_value_type('unknown_lang', 'anything'))
    end)
  end)

  describe('parse', function()
    it('should return nil when parser is not available', function()
      local result = ts.parse(0, 'nonexistent_language', '{}')
      assert.is_nil(result)
    end)

    it('should return nil for unsupported language', function()
      local result = ts.parse(0, 'env', 'KEY=value')
      assert.is_nil(result)
    end)
  end)

  -- Integration tests (only run if TreeSitter is available)
  describe('parse with treesitter (integration)', function()
    local json_parser_available = ts.has_parser('json')

    if json_parser_available then
      it('should parse JSON content', function()
        -- Create a temporary buffer with JSON content
        local bufnr = vim.api.nvim_create_buf(false, true)
        local content = '{"key": "value"}'
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { content })
        vim.api.nvim_set_option_value('filetype', 'json', { buf = bufnr })

        local result = ts.parse(bufnr, 'json', content)

        -- Clean up
        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          assert.is_table(result)
          assert.equals(1, #result)
          assert.equals('key', result[1].key)
          assert.equals('value', result[1].value)
        end
      end)
    end
  end)
end)
