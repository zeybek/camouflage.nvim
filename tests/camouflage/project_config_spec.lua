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

  describe('untrusted project files', function()
    local function write_project(lines)
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile(lines, dir .. '/.camouflage.yaml')
      vim.cmd('cd ' .. vim.fn.fnameescape(dir))
      return dir
    end

    local function has_error(status, text)
      for _, err in ipairs(status.errors) do
        if err:find(text, 1, true) then
          return true
        end
      end
      return false
    end

    it('cannot turn on HIBP network checks', function()
      write_project({
        'version: 1',
        'pwned:',
        '  auto_check: true',
        '  check_on_save: true',
        '  sign_text: "P"',
        'checks:',
        '  pwned:',
        '    check_on_change: true',
      })

      config.setup()
      local cfg = config.get()
      local status = project_config.status()

      assert.is_true(status.loaded)
      assert.is_false(cfg.pwned.auto_check)
      assert.is_false(cfg.pwned.check_on_save)
      assert.is_false(cfg.pwned.check_on_change)
      assert.is_false(cfg.checks.pwned.check_on_change)
      -- Other pwned options from the file still apply.
      assert.equals('P', cfg.pwned.sign_text)
      assert.is_true(has_error(status, 'pwned.auto_check'))
      assert.is_true(has_error(status, 'checks.pwned.check_on_change'))
    end)

    it('does not create HIBP autocmds from an untrusted file', function()
      write_project({ 'version: 1', 'pwned:', '  auto_check: true', '  check_on_change: true' })

      config.setup()
      local state = require('camouflage.state')
      require('camouflage.autocmds').setup()

      for _, au in ipairs(vim.api.nvim_get_autocmds({ group = state.augroup })) do
        assert.is_falsy(au.desc and au.desc:find('Camouflage pwned', 1, true))
      end
    end)

    it('can still turn HIBP network checks off', function()
      write_project({ 'version: 1', 'pwned:', '  auto_check: false' })

      config.setup({ pwned = { auto_check = true } })

      assert.is_false(config.get().pwned.auto_check)
      assert.is_false(has_error(project_config.status(), 'auto_check'))
    end)

    it('lets a trusted file turn on HIBP network checks', function()
      write_project({ 'version: 1', 'pwned:', '  auto_check: true' })
      local original = vim.secure.read
      vim.secure.read = function(path)
        return table.concat(vim.fn.readfile(path), '\n')
      end
      config.setup({ project_config = { secure = true } })
      vim.secure.read = original

      assert.is_true(config.get().pwned.auto_check)
      assert.is_true(project_config.status().loaded)
    end)

    it('warns with the file path when it disables masking', function()
      write_project({ 'version: 1', 'enabled: false' })
      local messages = {}
      local original = vim.notify_once
      vim.notify_once = function(msg)
        table.insert(messages, msg)
      end
      config.setup()
      vim.notify_once = original

      assert.is_false(config.get().enabled)
      local path = project_config.status().path
      local warned = false
      for _, msg in ipairs(messages) do
        if
          msg:find('masking is disabled by project config', 1, true) and msg:find(path, 1, true)
        then
          warned = true
        end
      end
      assert.is_true(warned)
    end)
  end)

  describe('per repository', function()
    local buffers = {}

    local function make_repo(lines)
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      if lines then
        vim.fn.writefile(lines, dir .. '/.camouflage.yaml')
      end
      return dir
    end

    local function env_buffer(dir, secret)
      local bufnr = vim.api.nvim_create_buf(true, false)
      table.insert(buffers, bufnr)
      vim.api.nvim_buf_set_name(bufnr, dir .. '/.env')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'SECRET=' .. secret })
      return bufnr
    end

    local function mark_count(bufnr)
      local state = require('camouflage.state')
      return #vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
    end

    after_each(function()
      for _, bufnr in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      buffers = {}
    end)

    it('uses the project config of the repository the buffer is in', function()
      local repo_a = make_repo({ 'version: 1', 'enabled: false' })
      local repo_b = make_repo()
      vim.cmd('cd ' .. vim.fn.fnameescape(repo_b))

      config.setup()
      local buf_a = env_buffer(repo_a, 'repo-a-secret')
      local buf_b = env_buffer(repo_b, 'repo-b-secret')

      assert.is_true(config.get().enabled)
      assert.is_false(config.get_for_buffer(buf_a).enabled)
      assert.is_true(config.get_for_buffer(buf_b).enabled)
    end)

    it('does not apply the cwd project config to files outside that project', function()
      local repo_a = make_repo({ 'version: 1', 'enabled: false', 'style: dotted' })
      local repo_b = make_repo()
      vim.cmd('cd ' .. vim.fn.fnameescape(repo_a))

      config.setup()
      local buf_a = env_buffer(repo_a, 'repo-a-secret')
      local buf_b = env_buffer(repo_b, 'repo-b-secret')

      assert.is_false(config.get_for_buffer(buf_a).enabled)
      assert.is_true(config.get_for_buffer(buf_b).enabled)
      assert.equals('stars', config.get_for_buffer(buf_b).style)
    end)

    it('reloads the global config from cwd, not from the current buffer', function()
      local repo_a = make_repo({ 'version: 1', 'enabled: false' })
      local repo_b = make_repo({ 'version: 1', 'style: dotted' })
      vim.cmd('cd ' .. vim.fn.fnameescape(repo_b))

      config.setup()
      local buf_a = env_buffer(repo_a, 'repo-a-secret')
      vim.api.nvim_set_current_buf(buf_a)
      assert.is_true(config.reload_project_config())

      assert.is_true(config.get().enabled)
      assert.equals('dotted', config.get().style)
      assert.truthy(project_config.status().path:match('%.camouflage%.yaml$'))
    end)

    it('keeps a runtime toggle across reloads and applies it to every repository', function()
      local repo_a = make_repo({ 'version: 1', 'style: dotted' })
      vim.cmd('cd ' .. vim.fn.fnameescape(make_repo()))

      config.setup()
      local buf_a = env_buffer(repo_a, 'repo-a-secret')
      config.set('enabled', false)
      config.reload_project_config()

      assert.is_false(config.get().enabled)
      assert.is_false(config.get_for_buffer(buf_a).enabled)
      assert.equals('dotted', config.get_for_buffer(buf_a).style)
    end)

    it('keeps masking another repository after one repository disables it', function()
      local repo_a = make_repo({ 'version: 1', 'enabled: true' })
      local repo_b = make_repo()
      vim.cmd('cd ' .. vim.fn.fnameescape(repo_b))

      config.setup()
      require('camouflage.parsers').setup()
      local core = require('camouflage.core')
      local buf_a = env_buffer(repo_a, 'repo-a-secret')
      local buf_b = env_buffer(repo_b, 'repo-b-secret')
      core.apply_decorations(buf_b)
      assert.equals(1, mark_count(buf_b))

      vim.fn.writefile({ 'version: 1', 'enabled: false' }, repo_a .. '/.camouflage.yaml')
      vim.api.nvim_set_current_buf(buf_a)
      config.reload_project_config()
      core.apply_decorations(buf_a)
      core.apply_decorations(buf_b)

      assert.equals(0, mark_count(buf_a))
      assert.equals(1, mark_count(buf_b))
    end)
  end)

  describe('parser lookup cache', function()
    local custom_pattern_lines = {
      'version: 1',
      'custom_patterns:',
      '  - file_pattern: "*.secrets"',
      '    pattern: "^(%w+):%s*(.+)$"',
      '    key_capture: 1',
      '    value_capture: 2',
    }

    it('is cleared when the project config is reloaded', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ 'version: 1' }, dir .. '/.camouflage.yaml')
      vim.cmd('cd ' .. vim.fn.fnameescape(dir))
      config.setup()
      local parsers = require('camouflage.parsers')
      parsers.setup()

      local file = dir .. '/app.secrets'
      assert.is_nil(parsers.find_parser_for_file(file))

      vim.fn.writefile(custom_pattern_lines, dir .. '/.camouflage.yaml')
      assert.is_true(config.reload_project_config())

      local _, name = parsers.find_parser_for_file(file)
      assert.equals('custom', name)
    end)

    it('is cleared when patterns change through config.set', function()
      vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.tempname():match('^(.*)/')))
      config.setup({ project_config = { enabled = false } })
      local parsers = require('camouflage.parsers')
      parsers.setup()

      assert.is_nil(parsers.find_parser_for_file('/tmp/project/app.secrets'))

      config.set('custom_patterns', {
        {
          file_pattern = '*.secrets',
          pattern = '^(%w+):%s*(.+)$',
          key_capture = 1,
          value_capture = 2,
        },
      })

      local _, name = parsers.find_parser_for_file('/tmp/project/app.secrets')
      assert.equals('custom', name)
    end)

    it('masks the current file after a refresh adds a pattern for it', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ 'version: 1' }, dir .. '/.camouflage.yaml')
      vim.fn.writefile({ 'token: cache-stale-secret' }, dir .. '/app.secrets')
      vim.cmd('cd ' .. vim.fn.fnameescape(dir))

      local camouflage = require('camouflage')
      camouflage.setup({ project_config = { watch_enabled = false } })
      vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/app.secrets'))
      local bufnr = vim.api.nvim_get_current_buf()
      local state = require('camouflage.state')
      assert.equals(0, #vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {}))

      vim.fn.writefile(custom_pattern_lines, dir .. '/.camouflage.yaml')
      camouflage.project_config_refresh()

      local marks = #vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, {})
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.equals(1, marks)
    end)
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
