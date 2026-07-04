describe('camouflage.project_config', function()
  local plugin_root = vim.fn.getcwd()
  local project_config
  local config
  local original_cwd

  package.path = plugin_root .. '/lua/?.lua;' .. plugin_root .. '/lua/?/init.lua;' .. package.path

  local function clear_camouflage_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  before_each(function()
    original_cwd = vim.fn.getcwd()
    clear_camouflage_modules()
    project_config = require('camouflage.project_config')
    config = require('camouflage.config')
    config.options = {}
  end)

  after_each(function()
    vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
  end)

  it('should report unloaded status when no project config file exists', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local status = project_config.status()

    assert.is_false(status.loaded)
    assert.is_nil(status.path)
    assert.equals(0, #status.errors)
  end)

  it('should load valid yaml project config file', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'version: 1', 'style: dotted', 'debug: true' }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local status = project_config.status()

    assert.is_true(status.loaded)
    assert.is_truthy(status.path and status.path:match('%.camouflage%.yaml$'))
    assert.equals('dotted', config.get().style)
    assert.is_true(config.get().debug)
  end)

  it('should accept documented nil-default keys (e.g. mask_length)', function()
    -- mask_length has a nil default, so its type cannot be inferred from
    -- defaults; the NULLABLE_KEYS allowlist must accept it instead of rejecting
    -- it as unknown.
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'version: 1', 'mask_length: 8' }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local status = project_config.status()
    assert.is_true(status.loaded)
    assert.equals(0, #status.errors)
    assert.equals(8, config.get().mask_length)
  end)

  it('should reject a documented nil-default key with the wrong type', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'version: 1', 'mask_length: notanumber' }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local status = project_config.status()
    assert.is_true(#status.errors > 0)
    assert.is_nil(config.get().mask_length)
  end)

  it('does not apply an untrusted project config when secure is enabled', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'version: 1', 'style: dotted' }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    -- Simulate an untrusted/denied file: vim.secure.read returns nil.
    local original = vim.secure.read
    vim.secure.read = function()
      return nil
    end
    config.setup({ project_config = { secure = true } })
    vim.secure.read = original

    local status = project_config.status()
    assert.is_false(status.loaded)
    assert.is_true(#status.errors > 0)
    -- The global default style is untouched (the repo file was not applied).
    assert.equals('stars', config.get().style)
  end)

  it('applies the project config when secure is disabled (default)', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'version: 1', 'style: dotted' }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    assert.equals('dotted', config.get().style)
  end)

  it('should ignore unknown top-level keys', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'version: 1', 'not_a_real_option: true' }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local status = project_config.status()

    assert.is_true(status.loaded)
    assert.is_true(#status.errors > 0)
    assert.is_nil(config.get().not_a_real_option)
  end)

  it('should not apply invalid project config version', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'version: 99', 'style: dotted' }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup({ style = 'stars' })
    local status = project_config.status()

    assert.is_false(status.loaded)
    assert.equals('stars', config.get().style)
    assert.is_true(#status.errors > 0)
  end)

  it('should parse YAML list items (patterns array)', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({
      'version: 1',
      'patterns:',
      "  - file_pattern: ['*.json']",
      '    parser: json',
      "  - file_pattern: ['*.yaml', '*.yml']",
      '    parser: yaml',
    }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local status = project_config.status()
    local patterns = config.get().patterns

    assert.is_true(status.loaded)
    assert.equals(2, #patterns)
    assert.equals('json', patterns[1].parser)
    assert.equals('yaml', patterns[2].parser)
  end)

  it('should load audit configuration', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({
      'version: 1',
      'audit:',
      "  ignore_patterns: ['tmp/**', 'fixtures/**']",
      '  max_files_per_chunk: 2',
      '  destination: loclist',
      '  open: false',
      '  notify: false',
    }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local audit = config.get().audit

    assert.same({ 'tmp/**', 'fixtures/**' }, audit.ignore_patterns)
    assert.equals(2, audit.max_files_per_chunk)
    assert.equals('loclist', audit.destination)
    assert.is_false(audit.open)
    assert.is_false(audit.notify)
  end)
end)
