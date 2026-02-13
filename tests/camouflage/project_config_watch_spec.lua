describe('camouflage.project_config_watch', function()
  local config
  local project_config
  local watch
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
    config = require('camouflage.config')
    project_config = require('camouflage.project_config')
    watch = require('camouflage.project_config_watch')
    assert.is_table(project_config)
    config.options = {}
    config.user_options = {}
  end)

  after_each(function()
    watch.stop()
    vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
  end)

  it('should stay disabled when watch_enabled is false', function()
    config.setup({
      project_config = {
        watch_enabled = false,
      },
    })

    watch.setup(function() end)
    local status = watch.status()
    assert.is_false(status.enabled)
    assert.equals(0, status.root_count)
  end)

  it('should attach a root watcher from opened buffers', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'version: 1', 'style: dotted' }, dir .. '/.camouflage.yaml')
    vim.fn.writefile({ 'API_KEY=secret' }, dir .. '/test.env')
    vim.cmd('cd ' .. vim.fn.fnameescape(dir))

    config.setup({
      project_config = {
        watch_enabled = true,
        watch_backend = 'autocmd',
      },
    })

    watch.setup(function() end)

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, dir .. '/test.env')
    vim.api.nvim_exec_autocmds('BufEnter', { buffer = bufnr })

    local status = watch.status()
    assert.is_true(status.enabled)
    assert.is_true(status.root_count >= 1)
  end)
end)
