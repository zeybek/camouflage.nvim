describe('camouflage.init_command', function()
  local init_command

  local function clear_camouflage_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function capture_notify()
    local calls = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(calls, { msg = msg, level = level })
    end
    return calls, function()
      vim.notify = original_notify
    end
  end

  before_each(function()
    clear_camouflage_modules()
    require('camouflage').setup()
    init_command = require('camouflage.init_command')
  end)

  describe('_get_plugin_path', function()
    it('should return valid path', function()
      local path = init_command._get_plugin_path()
      assert.is_not_nil(path)
      assert.is_true(type(path) == 'string')
      assert.is_true(#path > 0)
    end)

    it('should return path that contains lua/camouflage', function()
      local path = init_command._get_plugin_path()
      -- The path should be the plugin root, so lua/camouflage should exist under it
      local camouflage_dir = path .. '/lua/camouflage'
      assert.equals(1, vim.fn.isdirectory(camouflage_dir))
    end)
  end)

  describe('_read_template', function()
    it('should return content', function()
      local content, err = init_command._read_template()
      assert.is_nil(err)
      assert.is_not_nil(content)
      assert.is_true(type(content) == 'string')
    end)

    it('should return content starting with yaml-language-server schema', function()
      local content, _ = init_command._read_template()
      assert.is_not_nil(content)
      assert.is_true(content:match('^# yaml%-language%-server') ~= nil)
    end)

    it('should contain version: 1', function()
      local content, _ = init_command._read_template()
      assert.is_not_nil(content)
      assert.is_true(content:match('version: 1') ~= nil)
    end)

    it('should document all built-in parser names and default project patterns', function()
      local content, _ = init_command._read_template()
      assert.is_not_nil(content)

      for _, parser in ipairs({
        'env',
        'json',
        'yaml',
        'toml',
        'properties',
        'netrc',
        'xml',
        'http',
        'hcl',
        'dockerfile',
      }) do
        assert.is_not_nil(content:find(parser, 1, true), 'missing parser: ' .. parser)
      end

      assert.is_not_nil(content:find("file_pattern: ['*.tf', '*.tfvars', '*.hcl']", 1, true))
      assert.is_not_nil(content:find("'Dockerfile'", 1, true))
      assert.is_not_nil(content:find("'Dockerfile.*'", 1, true))
      assert.is_not_nil(content:find("'*.dockerfile'", 1, true))
      assert.is_not_nil(content:find("'Containerfile'", 1, true))
      assert.is_not_nil(content:find("'Containerfile.*'", 1, true))
      assert.is_not_nil(content:find('parser: dockerfile', 1, true))
    end)

    it('should include schema-supported parser settings examples', function()
      local content, _ = init_command._read_template()
      assert.is_not_nil(content)

      assert.is_not_nil(content:find('xml:', 1, true))
      assert.is_not_nil(content:find('hcl:', 1, true))
      assert.is_not_nil(content:find('dockerfile:', 1, true))
      assert.is_not_nil(content:find('No parser-specific options currently', 1, true))
    end)
  end)

  describe('_get_project_root', function()
    it('should return non-empty string', function()
      local root = init_command._get_project_root()
      assert.is_not_nil(root)
      assert.is_true(type(root) == 'string')
      assert.is_true(#root > 0)
    end)
  end)

  describe('init', function()
    local test_dir
    local original_cwd

    before_each(function()
      -- Create a temporary test directory
      test_dir = vim.fn.tempname()
      vim.fn.mkdir(test_dir, 'p')
      original_cwd = vim.fn.getcwd()
      vim.cmd('cd ' .. vim.fn.fnameescape(test_dir))
    end)

    after_each(function()
      -- Restore original cwd and cleanup
      vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
      vim.fn.delete(test_dir, 'rf')
    end)

    it('should create file in test directory', function()
      local notify_calls, restore_notify = capture_notify()
      local result = init_command.init({ force = true, open = false })
      restore_notify()

      assert.is_true(result, vim.inspect(notify_calls))

      local target = test_dir .. '/.camouflage.yaml'
      assert.equals(1, vim.fn.filereadable(target))
    end)

    it('should create file with correct content', function()
      local notify_calls, restore_notify = capture_notify()
      local result = init_command.init({ force = true, open = false })
      restore_notify()

      assert.is_true(result, vim.inspect(notify_calls))
      local target = test_dir .. '/.camouflage.yaml'
      local lines = vim.fn.readfile(target)
      local content = table.concat(lines, '\n')

      assert.is_true(content:match('^# yaml%-language%-server') ~= nil)
      assert.is_true(content:match('version: 1') ~= nil)
      assert.is_not_nil(content:find("file_pattern: ['*.tf', '*.tfvars', '*.hcl']", 1, true))
      assert.is_not_nil(content:find('parser: dockerfile', 1, true))
    end)
  end)

  describe('CamouflageInit command', function()
    it('should be registered', function()
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands['CamouflageInit'])
    end)

    it('should support bang modifier', function()
      local commands = vim.api.nvim_get_commands({})
      assert.is_true(commands['CamouflageInit'].bang)
    end)
  end)
end)
