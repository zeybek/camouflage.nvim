-- The audit as data, for a CI step. Same records the quickfix list is built
-- from, and like that list it never carries a value.
describe('camouflage.audit report', function()
  local audit
  local dir

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function scan()
    return audit.run({ path = dir, async = false })
  end

  before_each(function()
    clear_modules()
    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
    })
    audit = require('camouflage.audit')

    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'API_KEY=audit-secret', 'DEBUG=true' }, dir .. '/.env')
    vim.fn.writefile({ '{"token": "json-secret"}' }, dir .. '/config.json')
    vim.fn.writefile({ 'print("nothing here")' }, dir .. '/main.lua')
  end)

  after_each(function()
    vim.fn.delete(dir, 'rf')
  end)

  it('reports every value it would mask', function()
    local report = audit.to_report(scan())

    assert.equals(3, #report.findings)
    local keys = {}
    for _, finding in ipairs(report.findings) do
      keys[finding.key] = finding
    end
    assert.is_not_nil(keys.API_KEY)
    assert.equals('env', keys.API_KEY.parser)
    assert.equals(1, keys.API_KEY.lnum)
    assert.equals(#'audit-secret', keys.API_KEY.value_length)
    assert.equals('json', keys.token.parser)
  end)

  it('carries no value anywhere in it', function()
    local encoded = vim.json.encode(audit.to_report(scan()))

    assert.is_nil(encoded:find('audit-secret', 1, true))
    assert.is_nil(encoded:find('json-secret', 1, true))
  end)

  it('says what produced it', function()
    local report = audit.to_report(scan())

    assert.equals(1, report.version)
    assert.is_string(report.plugin_version)
    assert.equals(dir, report.root)
    assert.is_true(vim.tbl_contains(report.parsers, 'env'))
    assert.is_table(report.stats)
  end)

  it('keeps the policy decision, not the rule that made it', function()
    require('camouflage.config').set('policy.rules', {
      { id = 'ignore-debug', action = 'ignore', key = { '^DEBUG$' } },
    })
    local report = audit.to_report(scan())

    for _, finding in ipairs(report.findings) do
      assert.is_not_nil(finding.policy)
      assert.is_string(finding.policy.action)
      assert.is_nil(finding.policy.value)
    end
    require('camouflage.config').set('policy.rules', {})
  end)

  it('writes the report to a file', function()
    local out = dir .. '/report.json'
    assert.is_true(audit.write_report(scan(), out))

    local decoded = vim.json.decode(table.concat(vim.fn.readfile(out), '\n'))
    assert.equals(3, #decoded.findings)
  end)

  it('says so when the file cannot be written', function()
    local ok, err = audit.write_report(scan(), dir .. '/missing/report.json')

    assert.is_false(ok)
    assert.is_string(err)
  end)

  it('reports an empty project as empty rather than failing', function()
    local empty = vim.fn.tempname()
    vim.fn.mkdir(empty, 'p')
    vim.fn.writefile({ 'print("hi")' }, empty .. '/main.lua')

    local report = audit.to_report(audit.run({ path = empty, async = false }))

    assert.equals(0, #report.findings)
    assert.equals(0, #report.errors)
    vim.fn.delete(empty, 'rf')
  end)
end)
