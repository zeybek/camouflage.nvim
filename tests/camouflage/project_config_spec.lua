describe('camouflage.project_config', function()
  local project_config
  local config
  local original_cwd

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
end)
