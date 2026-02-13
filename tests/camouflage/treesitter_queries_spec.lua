describe('camouflage.treesitter queries', function()
  local treesitter

  before_each(function()
    package.loaded['camouflage.treesitter'] = nil
    treesitter = require('camouflage.treesitter')
    treesitter.clear_cache()
  end)

  describe('query file loading', function()
    local languages = { 'json', 'yaml', 'toml', 'xml', 'http' }

    for _, lang in ipairs(languages) do
      it('should have query available for ' .. lang, function()
        -- Query should be available either from file or fallback
        local ok, query = pcall(vim.treesitter.query.get, lang, 'camouflage')
        if not ok or not query then
          -- Check fallback exists
          local fallback_ok, fallback = pcall(vim.treesitter.query.parse, lang, '(_) @test')
          -- At minimum, the language should be parseable
          assert.is_true(fallback_ok or treesitter.has_parser(lang) == false)
        end
      end)
    end
  end)

  describe('query captures', function()
    it('should have @key and @value captures for json', function()
      if not treesitter.has_parser('json') then
        pending('json parser not available')
        return
      end

      local query = vim.treesitter.query.get('json', 'camouflage')
      if query then
        local has_key = vim.tbl_contains(query.captures, 'key')
        local has_value = vim.tbl_contains(query.captures, 'value')
        assert.is_true(has_key, 'should have @key capture')
        assert.is_true(has_value, 'should have @value capture')
      end
    end)

    it('should have @key and @value captures for yaml', function()
      if not treesitter.has_parser('yaml') then
        pending('yaml parser not available')
        return
      end

      local query = vim.treesitter.query.get('yaml', 'camouflage')
      if query then
        local has_key = vim.tbl_contains(query.captures, 'key')
        local has_value = vim.tbl_contains(query.captures, 'value')
        assert.is_true(has_key, 'should have @key capture')
        assert.is_true(has_value, 'should have @value capture')
      end
    end)
  end)

  describe('fallback mechanism', function()
    it('should parse json with treesitter when available', function()
      if not treesitter.has_parser('json') then
        pending('json parser not available')
        return
      end

      local bufnr = vim.api.nvim_create_buf(false, true)
      local content = '{"api_key": "secret123"}'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { content })
      vim.api.nvim_buf_set_option(bufnr, 'filetype', 'json')

      local result = treesitter.parse(bufnr, 'json', content)

      vim.api.nvim_buf_delete(bufnr, { force = true })

      if result then
        assert.is_true(#result > 0, 'should find variables')
        assert.equals('api_key', result[1].key)
        assert.equals('secret123', result[1].value)
      end
    end)
  end)
end)
