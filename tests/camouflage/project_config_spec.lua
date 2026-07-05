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

  it('should load generated template with current built-in parser coverage', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local template = require('camouflage.init_command')._read_template()
    vim.fn.writefile(vim.split(template, '\n', { plain = true }), dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local status = project_config.status()
    local patterns_by_parser = {}
    for _, entry in ipairs(config.get().patterns) do
      patterns_by_parser[entry.parser] = entry.file_pattern
    end

    assert.is_true(status.loaded)
    assert.equals(0, #status.errors)
    assert.same({ '*.tf', '*.tfvars', '*.hcl' }, patterns_by_parser.hcl)
    assert.same({
      'Dockerfile',
      'Dockerfile.*',
      '*.dockerfile',
      'Containerfile',
      'Containerfile.*',
    }, patterns_by_parser.dockerfile)
    assert.equals(10, config.get().parsers.xml.max_depth)
    assert.equals(10, config.get().parsers.hcl.max_depth)
    assert.same({}, config.get().parsers.dockerfile)
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

  it('should load policy configuration', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({
      'version: 1',
      'policy:',
      '  enabled: true',
      '  default_action: mask',
      "  terminal_path_ignores: ['vendor/**']",
      '  rules:',
      '    - id: ignore-debug',
      '      action: ignore',
      "      key: ['^DEBUG$']",
      "      parser: ['env']",
      '    - id: force-client-secret',
      '      action: mask',
      '      allow_force: true',
      "      key: ['^CLIENT_SECRET$']",
    }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local policy = config.get().policy

    assert.is_true(policy.enabled)
    assert.equals('mask', policy.default_action)
    assert.same({ 'vendor/**' }, policy.terminal_path_ignores)
    assert.equals('ignore-debug', policy.rules[1].id)
    assert.equals('force-client-secret', policy.rules[2].id)
    assert.is_true(policy.rules[2].allow_force)
  end)

  it('should fail closed when project policy contains an invalid rule', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({
      'version: 1',
      'policy:',
      '  rules:',
      '    - id: invalid-rule',
      '      action: drop',
      "      key: ['SECRET']",
    }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    local calls = {}
    local original_notify = vim.notify
    local original_notify_once = vim.notify_once
    vim.notify = function(msg, level)
      table.insert(calls, { msg = msg, level = level })
    end
    vim.notify_once = vim.notify

    config.setup()
    local policy = require('camouflage.policy')
    policy._reset_warnings()
    local decision = policy.evaluate({
      filename = dir .. '/app.env',
      root = dir,
      parser_name = 'env',
      variable = {
        key = 'SECRET',
        value = 'plaintext-secret',
      },
    }, config.get().policy)

    vim.notify = original_notify
    vim.notify_once = original_notify_once

    assert.equals('mask', decision.action)
    assert.equals(1, #calls)
    assert.equals(vim.log.levels.WARN, calls[1].level)
    assert.is_nil(calls[1].msg:find('plaintext-secret', 1, true))
  end)

  it('should load weak-secret check configuration', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({
      'version: 1',
      'checks:',
      '  weak_secret:',
      '    enabled: false',
      '    min_sensitive_length: 16',
      "    ignored_key_patterns: ['^TEST_']",
      "    ignored_value_patterns: ['^example$']",
    }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup()
    local weak_secret = config.get().checks.weak_secret

    assert.is_false(weak_secret.enabled)
    assert.equals(16, weak_secret.min_sensitive_length)
    assert.same({ '^TEST_' }, weak_secret.ignored_key_patterns)
    assert.same({ '^example$' }, weak_secret.ignored_value_patterns)
  end)

  it('should load custom check configuration without registering executable checks', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({
      'version: 1',
      'checks:',
      '  local_policy:',
      '    enabled: false',
      '    label: project',
      '    run: "return function() end"',
    }, dir .. '/.camouflage.yaml')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    local registry = require('camouflage.checks.registry')
    registry._reset()

    config.setup()
    local local_policy = config.get().checks.local_policy

    assert.is_false(local_policy.enabled)
    assert.equals('project', local_policy.label)
    assert.equals('return function() end', local_policy.run)
    assert.equals(0, #registry.list())
  end)
end)
