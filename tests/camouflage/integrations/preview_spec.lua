-- Previews of the other pickers, and blink.cmp. The pickers are not installed
-- in CI, so their hooks are exercised through stand-ins that have the same
-- shape as the real ones.
describe('camouflage.integrations.preview', function()
  local preview
  local config
  local buffers = {}
  local dir
  local envfile

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') or name:match('^fzf%-lua') or name:match('^mini') then
        package.loaded[name] = nil
      end
    end
  end

  local function scratch(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(buffers, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
  end

  local function masked_marks(bufnr)
    local count = 0
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
      if mark[4].virt_text then
        count = count + 1
      end
    end
    return count
  end

  before_each(function()
    clear_modules()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    envfile = dir .. '/.env'
    vim.fn.writefile({ 'API_KEY=preview-secret', 'DEBUG=true' }, envfile)

    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
    })
    config = require('camouflage.config')
    preview = require('camouflage.integrations.preview')
    preview._reset()
  end)

  after_each(function()
    package.loaded['fzf-lua.previewer.builtin'] = nil
    package.loaded['mini.pick'] = nil
    package.loaded['blink.cmp'] = nil
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
    vim.fn.delete(dir, 'rf')
  end)

  describe('mask_buffer', function()
    it('masks a preview buffer as the file it shows', function()
      local bufnr = scratch({ 'API_KEY=preview-secret', 'DEBUG=true' })

      assert.is_true(preview.mask_buffer(bufnr, envfile))
      assert.equals(2, masked_marks(bufnr))
    end)

    it('leaves a preview of a file no parser handles alone', function()
      local bufnr = scratch({ 'local token = "preview-secret"' })

      assert.is_false(preview.mask_buffer(bufnr, dir .. '/config.lua'))
      assert.equals(0, masked_marks(bufnr))
    end)

    it('does nothing while masking is off', function()
      local bufnr = scratch({ 'API_KEY=preview-secret' })
      config.set('enabled', false)

      assert.is_false(preview.mask_buffer(bufnr, envfile))
      config.set('enabled', true)
    end)

    it('does nothing without a buffer or a name', function()
      assert.is_false(preview.mask_buffer(nil, envfile))
      assert.is_false(preview.mask_buffer(scratch({ 'API_KEY=x' }), nil))
    end)
  end)

  describe('fzf-lua', function()
    local calls

    local function install_stub()
      calls = {}
      package.loaded['fzf-lua.previewer.builtin'] = {
        buffer_or_file = {
          preview_buf_post = function(_, entry)
            table.insert(calls, entry)
          end,
        },
      }
    end

    it('masks the preview buffer after the previewer filled it', function()
      install_stub()
      preview.setup()

      local bufnr = scratch({ 'API_KEY=preview-secret', 'DEBUG=true' })
      local builtin = require('fzf-lua.previewer.builtin')
      builtin.buffer_or_file.preview_buf_post({ preview_bufnr = bufnr }, { path = envfile })

      assert.equals(1, #calls, 'the original previewer still runs')
      assert.equals(2, masked_marks(bufnr))
    end)

    it('wraps the previewer once', function()
      install_stub()
      preview.setup()
      local wrapped = require('fzf-lua.previewer.builtin').buffer_or_file.preview_buf_post
      preview.setup()

      assert.equals(wrapped, require('fzf-lua.previewer.builtin').buffer_or_file.preview_buf_post)
    end)

    it('stays out of the way when the integration is off', function()
      install_stub()
      config.set('integrations.fzf', false)
      local before = require('fzf-lua.previewer.builtin').buffer_or_file.preview_buf_post
      preview.setup()

      assert.equals(before, require('fzf-lua.previewer.builtin').buffer_or_file.preview_buf_post)
      config.set('integrations.fzf', true)
    end)
  end)

  describe('mini.pick', function()
    local function install_stub()
      package.loaded['mini.pick'] = {
        default_preview = function(buf_id, item)
          -- The real one takes a path or an item table, same as here.
          local path = type(item) == 'table' and item.path or item
          vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.fn.readfile(path))
        end,
      }
    end

    it('masks the preview buffer after mini.pick filled it', function()
      install_stub()
      preview.setup()

      local bufnr = scratch({})
      require('mini.pick').default_preview(bufnr, envfile)

      assert.equals(2, masked_marks(bufnr))
      assert.equals('API_KEY=preview-secret', vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1])
    end)

    it('takes the path off an item table too', function()
      install_stub()
      preview.setup()

      local bufnr = scratch({})
      require('mini.pick').default_preview(bufnr, { path = envfile, text = envfile })

      assert.equals(2, masked_marks(bufnr))
    end)
  end)

  describe('blink.cmp', function()
    local function open_env()
      vim.cmd('edit ' .. envfile)
      local bufnr = vim.api.nvim_get_current_buf()
      table.insert(buffers, bufnr)
      return bufnr
    end

    it('turns completion off in a masked buffer', function()
      local bufnr = open_env()
      preview.sync_blink(bufnr)

      assert.is_false(vim.b[bufnr].completion)
    end)

    it('puts the buffer back when masking stops', function()
      local bufnr = open_env()
      preview.sync_blink(bufnr)
      assert.is_false(vim.b[bufnr].completion)

      require('camouflage.core').clear_mask_state(bufnr)
      preview.sync_blink(bufnr)

      assert.is_nil(vim.b[bufnr].completion)
    end)

    it('gives back the value the user had set', function()
      local bufnr = open_env()
      vim.b[bufnr].completion = true
      preview.sync_blink(bufnr)
      assert.is_false(vim.b[bufnr].completion)

      require('camouflage.core').clear_mask_state(bufnr)
      preview.sync_blink(bufnr)

      assert.is_true(vim.b[bufnr].completion)
    end)

    it('leaves the buffer alone when the integration is off', function()
      config.set('integrations.blink', { disable_in_masked = false })
      local bufnr = open_env()
      preview.sync_blink(bufnr)

      assert.is_nil(vim.b[bufnr].completion)
      config.set('integrations.blink', { disable_in_masked = true })
    end)
  end)
end)
