-- The expensive half of a check depends only on the value, so a pass over a
-- file that didn't change should not redo it.
describe('camouflage checks reuse their answers', function()
  local core
  local config
  local buffers = {}

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function open(name, lines)
    local bufnr = vim.api.nvim_create_buf(true, false)
    table.insert(buffers, bufnr)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '/' .. name)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    require('camouflage.state').init_buffer(bufnr)
    core.apply_decorations(bufnr)
    return bufnr
  end

  ---Count the calls to a module function while `fn` runs.
  local function counting(module, name, fn)
    local target = require(module)
    local original = target[name]
    local calls = 0
    target[name] = function(...)
      calls = calls + 1
      return original(...)
    end
    local ok, err = pcall(fn)
    target[name] = original
    assert(ok, err)
    return calls
  end

  before_each(function()
    clear_modules()
    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
      pwned = { enabled = false },
    })
    core = require('camouflage.core')
    config = require('camouflage.config')
    require('camouflage.checks.memo').clear_all()
  end)

  after_each(function()
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
  end)

  it('scores a weak secret once, not on every pass', function()
    local bufnr = open('weak.env', { 'API_KEY=password', 'TOKEN=changeme123' })

    local calls = counting('camouflage.checks.weak_secret', 'classify', function()
      core.apply_decorations(bufnr)
      core.apply_decorations(bufnr)
      core.apply_decorations(bufnr)
    end)

    assert.equals(0, calls)
  end)

  it('scores a value again once it changes', function()
    local bufnr = open('changed.env', { 'API_KEY=password' })

    local calls = counting('camouflage.checks.weak_secret', 'classify', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { 'API_KEY=a-different-one' })
      core.apply_decorations(bufnr)
    end)

    assert.equals(1, calls)
  end)

  it('scores again after the config changes', function()
    local bufnr = open('reconfig.env', { 'API_KEY=password' })

    local calls = counting('camouflage.checks.weak_secret', 'classify', function()
      config.set('checks.weak_secret.min_length', 12)
      core.apply_decorations(bufnr)
    end)

    assert.equals(1, calls)
  end)

  it('keeps the badges it had', function()
    local bufnr = open('badges.env', { 'API_KEY=password' })
    local checks = require('camouflage.checks')
    local before = checks.store.get(bufnr, 0, 'weak_secret')
    assert.is_not_nil(before)

    core.apply_decorations(bufnr)

    local after = checks.store.get(bufnr, 0, 'weak_secret')
    assert.is_not_nil(after)
    assert.equals(before.text, after.text)
  end)

  it('decodes a JWT once, not on every pass', function()
    local token = 'eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjIwMDAwMDAwMDB9.sig'
    local bufnr = open('jwt.env', { 'ACCESS_TOKEN=' .. token })

    local calls = counting('camouflage.checks.expiry.jwt', 'decode', function()
      core.apply_decorations(bufnr)
      core.apply_decorations(bufnr)
    end)

    assert.equals(0, calls)
  end)

  it('forgets a buffer with its state', function()
    local bufnr = open('gone.env', { 'API_KEY=password' })
    local memo = require('camouflage.checks.memo')
    assert.is_true(memo.count(bufnr) > 0)

    require('camouflage.checks').clear_buffer(bufnr)

    assert.equals(0, memo.count(bufnr))
  end)

  describe('hooks', function()
    it('does nothing for an event nobody listens to', function()
      local hooks = require('camouflage.hooks')
      assert.is_nil(hooks.emit('variable_detected', 1, { key = 'K', value = 'v' }))
    end)

    it('still calls a listener that is registered', function()
      local hooks = require('camouflage.hooks')
      local seen = 0
      local id = hooks.on('variable_detected', function()
        seen = seen + 1
      end)

      hooks.emit('variable_detected', 1, { key = 'K', value = 'v' })
      hooks.off('variable_detected', id)

      assert.equals(1, seen)
    end)

    it('still fires the User autocmd for decorate events', function()
      local hooks = require('camouflage.hooks')
      local fired = 0
      local id = vim.api.nvim_create_autocmd('User', {
        pattern = 'CamouflageBeforeDecorate',
        callback = function()
          fired = fired + 1
        end,
      })

      hooks.emit('before_decorate', 1, 'file.env')
      vim.api.nvim_del_autocmd(id)

      assert.equals(1, fired)
    end)
  end)
end)
