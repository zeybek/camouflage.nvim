-- Pickers loaded after camouflage (packadd, opt packages, lazy.nvim) still get
-- their hooks, and setting camouflage up never loads a picker early.
describe('camouflage.integrations.later', function()
  local later
  local root
  local rtp
  local fake_modules = { 'snacks.picker.format', 'telescope.make_entry', 'mini.pick' }

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
    for _, name in ipairs(fake_modules) do
      package.loaded[name] = nil
    end
  end

  ---Write a fake plugin module under the temporary plugin directory.
  local function write_module(module, lines)
    local path = root .. '/lua/' .. module:gsub('%.', '/') .. '.lua'
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    vim.fn.writefile(lines, path)
  end

  local function add_plugin_to_rtp()
    vim.opt.rtp:append(root)
  end

  local function wait_installed(name)
    return vim.wait(1000, function()
      return not vim.tbl_contains(later.waiting(), name)
    end, 10)
  end

  before_each(function()
    rtp = vim.o.runtimepath
    root = vim.fn.tempname()
    write_module('snacks.picker.format', {
      'local M = {}',
      'function M.file(item) return { { item.line } } end',
      'return M',
    })
    write_module('telescope.make_entry', {
      'local M = {}',
      'function M.gen_from_vimgrep()',
      '  return function(line) return { filename = line:match("^[^:]+"), text = line:match("[^:]+$") } end',
      'end',
      'return M',
    })
    clear_modules()
    require('camouflage').setup({ project_config = { enabled = false, watch_enabled = false } })
    later = require('camouflage.integrations.later')
  end)

  after_each(function()
    vim.o.runtimepath = rtp
    later._reset()
    clear_modules()
    vim.fn.delete(root, 'rf')
  end)

  it('does not load a picker that is not there yet', function()
    assert.is_nil(package.loaded['snacks.picker.format'])
    assert.is_nil(package.loaded['telescope.make_entry'])
    assert.is_true(vim.tbl_contains(later.waiting(), 'picker_results.snacks'))
    assert.is_true(vim.tbl_contains(later.waiting(), 'picker_results.telescope'))
  end)

  it('masks snacks result rows once snacks is added with :packadd', function()
    add_plugin_to_rtp()
    vim.api.nvim_exec_autocmds('SourcePost', { pattern = root .. '/plugin/snacks.lua' })
    assert.is_true(
      wait_installed('picker_results.snacks'),
      'still waiting: ' .. table.concat(later.waiting(), ', ')
    )

    local format = require('snacks.picker.format')
    local row = format.file({ file = vim.fn.getcwd() .. '/.env', line = 'API_KEY=late-secret' })

    assert.is_nil(row[1][1]:find('late-secret', 1, true), row[1][1])
    assert.truthy(row[1][1]:find('API_KEY=', 1, true))
  end)

  it('masks telescope grep rows once lazy.nvim loads telescope', function()
    add_plugin_to_rtp()
    vim.api.nvim_exec_autocmds('User', { pattern = 'LazyLoad', data = 'telescope.nvim' })
    assert.is_true(
      wait_installed('picker_results.telescope'),
      'still waiting: ' .. table.concat(later.waiting(), ', ')
    )

    local maker = require('telescope.make_entry').gen_from_vimgrep({})
    local entry = maker(vim.fn.getcwd() .. '/.env:API_KEY=late-secret')

    assert.is_nil(entry.text:find('late-secret', 1, true), entry.text)
  end)

  it('installs a hook right away when its picker is already there', function()
    later._reset()
    add_plugin_to_rtp()
    require('camouflage.integrations.picker')._reset()
    require('camouflage.integrations.picker').setup()

    assert.same({}, later.waiting())
  end)

  it('keeps the preview autocmds without the pickers installed', function()
    local group = require('camouflage.state').integrations_augroup
    local function count(event, pattern)
      return #vim.api.nvim_get_autocmds({ group = group, event = event, pattern = pattern })
    end

    assert.equals(1, count('User', 'TelescopePreviewerLoaded'))
    assert.equals(1, count('FileType', 'snacks_picker_input'))
  end)

  it('does not install a hook whose integration was turned off meanwhile', function()
    assert.is_true(vim.tbl_contains(later.waiting(), 'preview.mini_pick'))
    require('camouflage.config').set('integrations.mini_pick', false)
    require('camouflage.integrations.preview').setup()

    local original = function() end
    package.loaded['mini.pick'] = { default_preview = original }
    later.try_all()

    assert.equals(original, package.loaded['mini.pick'].default_preview)
    assert.is_false(vim.tbl_contains(later.waiting(), 'preview.mini_pick'))
  end)

  it('says a module is available when it is loaded or on the runtimepath', function()
    assert.is_false(later.available('snacks.picker.format'))
    add_plugin_to_rtp()
    assert.is_true(later.available('snacks.picker.format'))
    package.loaded['mini.pick'] = {}
    assert.is_true(later.available('mini.pick'))
  end)
end)
