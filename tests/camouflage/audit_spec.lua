describe('camouflage.audit', function()
  local plugin_root = vim.fn.getcwd()
  local original_cwd

  package.path = plugin_root .. '/lua/?.lua;' .. plugin_root .. '/lua/?/init.lua;' .. package.path

  local function clear_camouflage_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function writefile(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    vim.fn.writefile(lines, path)
  end

  local function setup_in_dir(dir, opts)
    opts = opts or {}
    clear_camouflage_modules()
    local camouflage = require('camouflage')
    local audit = require('camouflage.audit')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))
    local base = {
      project_config = {
        watch_enabled = false,
      },
      audit = {
        open = false,
        notify = false,
      },
    }
    camouflage.setup(vim.tbl_deep_extend('force', base, opts))
    return audit, camouflage
  end

  local function inspect_has(value, needle)
    return vim.inspect(value):find(needle, 1, true) ~= nil
  end

  before_each(function()
    original_cwd = vim.fn.getcwd()
    vim.fn.setqflist({}, 'r')
    vim.fn.setloclist(0, {}, 'r')
  end)

  after_each(function()
    pcall(vim.cmd, 'cclose')
    pcall(vim.cmd, 'lclose')
    vim.fn.setqflist({}, 'r')
    vim.fn.setloclist(0, {}, 'r')
    vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
  end)

  it('scans supported files and returns redacted findings', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    writefile(dir .. '/.camouflage.yaml', { 'version: 1' })
    writefile(dir .. '/.env', { 'API_KEY=env-secret-should-not-return' })
    writefile(dir .. '/config.json', { '{"TOKEN": "json-secret-should-not-return"}' })
    writefile(dir .. '/notes.txt', { 'PASSWORD=unsupported-secret' })

    local audit = setup_in_dir(dir)
    local result = audit.run({ root = dir })

    assert.equals(2, #result.findings)
    assert.equals(0, #result.errors)
    for _, finding in ipairs(result.findings) do
      assert.is_nil(finding.value)
      assert.is_string(finding.filename)
      assert.is_number(finding.lnum)
      assert.is_number(finding.col)
      assert.is_string(finding.parser)
      assert.is_number(finding.value_length)
    end
    assert.is_false(inspect_has(result, 'env-secret-should-not-return'))
    assert.is_false(inspect_has(result, 'json-secret-should-not-return'))
    assert.is_false(inspect_has(result, 'unsupported-secret'))
  end)

  it('uses runtime registered parsers', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    writefile(dir .. '/app.kdl', { 'token "runtime-secret-should-not-return"' })

    local audit, camouflage = setup_in_dir(dir)
    camouflage.register_parser({
      name = 'kdl',
      file_patterns = { '*.kdl' },
      parser = {
        parse = function()
          return {
            {
              key = 'token',
              value = 'runtime-secret-should-not-return',
              start_index = 7,
              end_index = 39,
              line_number = 0,
              is_nested = false,
              is_commented = false,
            },
          }
        end,
      },
    })

    local result = audit.run({ root = dir })

    assert.equals(1, #result.findings)
    assert.equals('kdl', result.findings[1].parser)
    assert.equals('token', result.findings[1].key)
    assert.is_false(inspect_has(result, 'runtime-secret-should-not-return'))
  end)

  it('uses custom pattern configuration', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    writefile(dir .. '/app.secret', { 'SECRET: custom-secret-should-not-return' })

    local audit = setup_in_dir(dir, {
      custom_patterns = {
        {
          file_pattern = '*.secret',
          pattern = 'SECRET:%s*(.+)',
          value_capture = 1,
        },
      },
    })

    local result = audit.run({ root = dir })

    assert.equals(1, #result.findings)
    assert.equals('custom', result.findings[1].parser)
    assert.equals('custom_1', result.findings[1].key)
    assert.is_false(inspect_has(result, 'custom-secret-should-not-return'))
  end)

  it('applies policy and returns redacted policy metadata', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    writefile(dir .. '/.env', { 'DEBUG=true', 'API_KEY=audit-secret-should-not-return' })

    local audit = setup_in_dir(dir, {
      policy = {
        rules = {
          { id = 'ignore-debug', action = 'ignore', key = { '^DEBUG$' } },
        },
      },
    })

    local result = audit.run({ root = dir })

    assert.equals(1, #result.findings)
    assert.equals('API_KEY', result.findings[1].key)
    assert.equals(1, result.stats.policy_ignored)
    assert.equals('mask', result.findings[1].policy.action)
    assert.equals('default', result.findings[1].policy.reason)
    assert.is_false(inspect_has(result, 'audit-secret-should-not-return'))
  end)

  it('skips project config, unsupported files, oversized files, and ignored paths', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    writefile(dir .. '/.camouflage.yaml', { 'version: 1', 'hidden_text: project-config-value' })
    writefile(dir .. '/keep.env', { 'KEEP=mask-me' })
    writefile(dir .. '/big.env', { 'ONE=1', 'TWO=2' })
    writefile(dir .. '/ignored/skip.env', { 'SKIP=ignore-me' })
    writefile(dir .. '/notes.txt', { 'NOTE=unsupported' })

    local audit = setup_in_dir(dir, {
      max_lines = 1,
      audit = {
        ignore_patterns = { 'ignored', 'ignored/**' },
      },
    })

    local result = audit.run({ root = dir })

    assert.equals(1, #result.findings)
    assert.equals('KEEP', result.findings[1].key)
    assert.is_false(inspect_has(result, 'project-config-value'))
    assert.is_false(inspect_has(result, 'ignore-me'))
  end)

  it('continues after parser errors without returning parser error plaintext', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    writefile(dir .. '/ok.env', { 'OK=still-found' })
    writefile(dir .. '/bad.err', { 'BAD=parser-error-secret' })

    local audit, camouflage = setup_in_dir(dir)
    camouflage.register_parser({
      name = 'broken',
      file_patterns = { '*.err' },
      parser = {
        parse = function()
          error('parser saw parser-error-secret')
        end,
      },
    })

    local result = audit.run({ root = dir })

    assert.equals(1, #result.findings)
    assert.equals(1, #result.errors)
    assert.equals('broken', result.errors[1].parser)
    assert.equals('parser failed', result.errors[1].message)
    assert.is_false(inspect_has(result, 'parser-error-secret'))
  end)

  it('runs asynchronously in chunks and supports cancellation', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    for i = 1, 5 do
      writefile(dir .. '/file' .. i .. '.env', { 'KEY' .. i .. '=value' .. i })
    end

    local audit = setup_in_dir(dir)
    local done = false
    local final_result
    local progress_count = 0
    local handle

    handle = audit.run({
      root = dir,
      async = true,
      max_files_per_chunk = 1,
      on_progress = function(progress)
        progress_count = progress_count + 1
        if progress.files_done >= 1 then
          handle.cancel()
        end
      end,
      on_complete = function(result)
        final_result = result
        done = true
      end,
    })

    vim.wait(1000, function()
      return done
    end)

    assert.is_true(done)
    assert.is_true(progress_count > 0)
    assert.is_true(final_result.cancelled)
    assert.is_true(final_result.stats.files_scanned < final_result.stats.files_seen)
  end)

  it('writes quickfix entries without values and clears stale entries on empty results', function()
    local dir = vim.fn.tempname()
    local empty_dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.mkdir(empty_dir, 'p')
    writefile(dir .. '/.env', { 'API_KEY=qf-secret-should-not-return' })

    local audit = setup_in_dir(dir)
    local result = audit.run({ root = dir })
    audit.set_list(result, { destination = 'quickfix', open = false })

    local items = vim.fn.getqflist()
    assert.equals(1, #items)
    assert.matches('%[env%] API_KEY', items[1].text)
    assert.is_false(inspect_has(items, 'qf-secret-should-not-return'))

    local empty_result = audit.run({ root = empty_dir })
    audit.set_list(empty_result, { destination = 'quickfix', open = false })

    assert.equals(0, #vim.fn.getqflist())
  end)

  it('CamouflageAudit populates quickfix by default and bang populates location list', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    writefile(dir .. '/.env', { 'API_KEY=command-secret-should-not-return' })

    setup_in_dir(dir)

    assert.has_no.errors(function()
      vim.cmd('CamouflageAudit ' .. vim.fn.fnameescape(dir))
    end)
    vim.wait(1000, function()
      return #vim.fn.getqflist() > 0
    end)

    local qf = vim.fn.getqflist()
    assert.equals(1, #qf)
    assert.is_false(inspect_has(qf, 'command-secret-should-not-return'))

    assert.has_no.errors(function()
      vim.cmd('CamouflageAudit! ' .. vim.fn.fnameescape(dir))
    end)
    vim.wait(1000, function()
      return #vim.fn.getloclist(0) > 0
    end)

    local loc = vim.fn.getloclist(0)
    assert.equals(1, #loc)
    assert.is_false(inspect_has(loc, 'command-secret-should-not-return'))
  end)
end)
