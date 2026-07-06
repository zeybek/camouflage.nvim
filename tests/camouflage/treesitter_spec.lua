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

  -- Note: Query string tests moved to treesitter_queries_spec.lua
  -- Queries are now loaded from .scm files with fallback mechanism

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
    local yaml_parser_available = ts.has_parser('yaml')
    local toml_parser_available = ts.has_parser('toml')
    local xml_parser_available = ts.has_parser('xml')

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

      it('should expose nested JSON key paths', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local lines = {
          '{',
          '  "database": {',
          '    "connection": { "password": "secret" }',
          '  }',
          '}',
        }
        local content = table.concat(lines, '\n')
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value('filetype', 'json', { buf = bufnr })

        local result = ts.parse(bufnr, 'json', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          local by_key = {}
          for _, v in ipairs(result) do
            by_key[v.key] = v
            assert.equals(v.value, content:sub(v.start_index + 1, v.end_index))
          end
          assert.equals('secret', by_key['database.connection.password'].value)
          assert.is_true(by_key['database.connection.password'].is_nested)
        end
      end)
    end

    if yaml_parser_available then
      it('should parse YAML block style content', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local content = 'api_key: secret123'
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { content })
        vim.api.nvim_set_option_value('filetype', 'yaml', { buf = bufnr })

        local result = ts.parse(bufnr, 'yaml', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          assert.is_table(result)
          assert.equals(1, #result)
          assert.equals('api_key', result[1].key)
          assert.equals('secret123', result[1].value)
        end
      end)

      it('should parse YAML flow style content', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local content = 'config: {secret: hidden123, api_key: sk-999}'
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { content })
        vim.api.nvim_set_option_value('filetype', 'yaml', { buf = bufnr })

        local result = ts.parse(bufnr, 'yaml', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          assert.is_table(result)
          -- Should capture flow style values
          local keys = {}
          for _, v in ipairs(result) do
            keys[v.key] = v.value
          end
          assert.equals('hidden123', keys['config.secret'])
          assert.equals('sk-999', keys['config.api_key'])
        end
      end)

      it('should expose nested YAML block key paths', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local lines = {
          'database:',
          '  connection:',
          '    password: secret',
        }
        local content = table.concat(lines, '\n')
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value('filetype', 'yaml', { buf = bufnr })

        local result = ts.parse(bufnr, 'yaml', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          local by_key = {}
          for _, v in ipairs(result) do
            by_key[v.key] = v
            assert.equals(v.value, content:sub(v.start_index + 1, v.end_index))
          end
          assert.equals('secret', by_key['database.connection.password'].value)
          assert.is_true(by_key['database.connection.password'].is_nested)
        end
      end)

      it('should parse YAML quoted values', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local content = 'message: "Hello World"'
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { content })
        vim.api.nvim_set_option_value('filetype', 'yaml', { buf = bufnr })

        local result = ts.parse(bufnr, 'yaml', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          assert.is_table(result)
          assert.equals(1, #result)
          assert.equals('message', result[1].key)
          assert.equals('Hello World', result[1].value)
        end
      end)

      it('should parse YAML block scalars as multiline values', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local lines = {
          'certificates:',
          '  private_key: |',
          '    -----BEGIN RSA PRIVATE KEY-----',
          '    secret-key-material',
          '  certificate: >',
          '    folded certificate',
          '    material',
        }
        local content = table.concat(lines, '\n')
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value('filetype', 'yaml', { buf = bufnr })

        local result = ts.parse(bufnr, 'yaml', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          local by_key = {}
          for _, v in ipairs(result) do
            by_key[v.key] = v
            assert.equals(v.value, content:sub(v.start_index + 1, v.end_index))
          end
          assert.is_not_nil(by_key['certificates.private_key'])
          assert.is_true(by_key['certificates.private_key'].is_multiline)
          assert.is_true(by_key['certificates.private_key'].value:match('BEGIN RSA') ~= nil)
          assert.is_not_nil(by_key['certificates.certificate'])
          assert.is_true(by_key['certificates.certificate'].is_multiline)
          assert.is_true(
            by_key['certificates.certificate'].value:match('folded certificate') ~= nil
          )
        end
      end)

      it('should skip YAML flow mapping containers', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local content = 'outer: {inner: value}'
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { content })
        vim.api.nvim_set_option_value('filetype', 'yaml', { buf = bufnr })

        local result = ts.parse(bufnr, 'yaml', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          assert.is_table(result)
          -- Should only capture 'inner', not 'outer' (which has flow_mapping value)
          assert.equals(1, #result)
          assert.equals('outer.inner', result[1].key)
          assert.equals('value', result[1].value)
        end
      end)
    end

    if toml_parser_available then
      it('should expose TOML table key paths and unquoted string values', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local lines = {
          '[database]',
          'host = "localhost"',
          'password = "secret"',
          'port = 5432',
        }
        local content = table.concat(lines, '\n')
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value('filetype', 'toml', { buf = bufnr })

        local result = ts.parse(bufnr, 'toml', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          local by_key = {}
          for _, v in ipairs(result) do
            by_key[v.key] = v
            assert.equals(v.value, content:sub(v.start_index + 1, v.end_index))
          end
          assert.equals('localhost', by_key['database.host'].value)
          assert.equals('secret', by_key['database.password'].value)
          assert.equals('5432', by_key['database.port'].value)
          assert.is_true(by_key['database.password'].is_nested)
        end
      end)
    end

    if xml_parser_available then
      it('should expose nested XML element and attribute key paths', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local content =
          '<settings><database host="localhost" password="dbpass"><password>secret</password></database></settings>'
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { content })
        vim.api.nvim_set_option_value('filetype', 'xml', { buf = bufnr })

        local result = ts.parse(bufnr, 'xml', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          local by_key = {}
          for _, v in ipairs(result) do
            by_key[v.key] = v
            assert.equals(v.value, content:sub(v.start_index + 1, v.end_index))
          end
          assert.equals('localhost', by_key['settings.database@host'].value)
          assert.equals('dbpass', by_key['settings.database@password'].value)
          assert.equals('secret', by_key['settings.database.password'].value)
          assert.is_true(by_key['settings.database@password'].is_nested)
          assert.is_true(by_key['settings.database.password'].is_nested)
        end
      end)

      it('should include self-closing XML element names in attribute key paths', function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local content = '<settings><database host="localhost" password="dbpass"/></settings>'
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { content })
        vim.api.nvim_set_option_value('filetype', 'xml', { buf = bufnr })

        local result = ts.parse(bufnr, 'xml', content)

        vim.api.nvim_buf_delete(bufnr, { force = true })

        if result then
          local by_key = {}
          for _, v in ipairs(result) do
            by_key[v.key] = v
            assert.equals(v.value, content:sub(v.start_index + 1, v.end_index))
          end
          assert.equals('localhost', by_key['settings.database@host'].value)
          assert.equals('dbpass', by_key['settings.database@password'].value)
        end
      end)
    end
  end)
end)
