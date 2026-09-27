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
          -- The real one takes a path or an item table, same as here, and cuts
          -- a string item at the first NUL ("path\0lnum\0col\0text" for grep).
          local path = type(item) == 'table' and item.path or item:match('^[^%z]*')
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

    it('masks the preview of a grep item without erroring on its NUL separators', function()
      install_stub()
      preview.setup()

      local bufnr = scratch({})
      local item = envfile .. '\0' .. '1\0' .. '1\0' .. 'API_KEY=preview-secret'
      assert.has_no.errors(function()
        require('mini.pick').default_preview(bufnr, item)
      end)

      assert.equals(2, masked_marks(bufnr))
    end)

    it('reads the path of an item the way mini.pick does', function()
      assert.equals('a.env', preview.mini_pick_item_path('a.env\0' .. '3\0' .. '1\0' .. 'K=v'))
      assert.equals('a.env', preview.mini_pick_item_path('a.env'))
      assert.equals('b.env', preview.mini_pick_item_path({ path = 'b.env', lnum = 2 }))
      assert.is_nil(preview.mini_pick_item_path(42))
      assert.is_nil(preview.mini_pick_item_path(''))
    end)

    describe('pickers that start with a preview of their own', function()
      -- A stand-in for the active picker: its source keeps whatever preview it
      -- was started with, like mini.pick does when it normalizes the source.
      local picker_opts, set_calls

      local function start_picker(source_preview)
        picker_opts = { source = { preview = source_preview } }
        set_calls = 0
        package.loaded['mini.pick'].get_picker_opts = function()
          return vim.deepcopy(picker_opts)
        end
        package.loaded['mini.pick'].set_picker_opts = function(opts)
          set_calls = set_calls + 1
          picker_opts = vim.tbl_deep_extend('force', picker_opts, opts)
        end
        vim.api.nvim_exec_autocmds('User', { pattern = 'MiniPickStart' })
      end

      local function reader(buf_id, item)
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.fn.readfile(item))
      end

      it('masks a picker started with the plain default preview', function()
        install_stub()
        local plain = require('mini.pick').default_preview
        preview.setup()

        start_picker(plain)
        local bufnr = scratch({})
        picker_opts.source.preview(bufnr, envfile)

        assert.equals(1, set_calls)
        assert.equals(2, masked_marks(bufnr))
      end)

      it('masks a custom source.preview', function()
        install_stub()
        preview.setup()

        start_picker(reader)
        local bufnr = scratch({})
        picker_opts.source.preview(bufnr, envfile)

        assert.equals(2, masked_marks(bufnr))
      end)

      it('leaves a preview that already masks alone', function()
        install_stub()
        preview.setup()

        start_picker(require('mini.pick').default_preview)

        assert.equals(0, set_calls)
      end)

      it('does nothing when the integration is off', function()
        install_stub()
        config.set('integrations.mini_pick', false)
        preview.setup()

        start_picker(reader)

        assert.equals(0, set_calls)
        config.set('integrations.mini_pick', true)
      end)
    end)

    describe('result rows', function()
      local function to_line(item)
        return (type(item) == 'table' and item.text or item):gsub('%z', '│')
      end

      local function install_show_stub()
        install_stub()
        package.loaded['mini.pick'].default_show = function(buf_id, items)
          vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.tbl_map(to_line, items))
        end
      end

      local function row_marks(bufnr)
        local out = {}
        for _, m in
          ipairs(
            vim.api.nvim_buf_get_extmarks(
              bufnr,
              preview.mini_pick_namespace,
              0,
              -1,
              { details = true }
            )
          )
        do
          out[m[2] + 1] = { col = m[3], end_col = m[4].end_col, text = m[4].virt_text[1][1] }
        end
        return out
      end

      local function grep_item(path, text)
        return path .. '\0' .. '1\0' .. '1\0' .. text
      end

      it('covers the value of a grep row pointing into a supported file', function()
        install_show_stub()
        preview.setup()
        require('camouflage.integrations.later').try_all()

        local bufnr = scratch({})
        local items = {
          grep_item(envfile, 'API_KEY=row-secret'),
          grep_item(dir .. '/notes.txt', 'API_KEY=not-a-config'),
          envfile,
        }
        require('mini.pick').default_show(bufnr, items, {}, {})

        local marks = row_marks(bufnr)
        local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
        assert.is_table(marks[1], 'grep row was not masked')
        assert.equals('row-secret', line:sub(marks[1].col + 1, marks[1].end_col))
        assert.is_nil(marks[1].text:find('row-secret', 1, true))
        assert.is_nil(marks[2], 'row of an unsupported file was masked')
        assert.is_nil(marks[3], 'a plain path row was masked')
      end)

      it('masks the rows of a picker with a show function of its own', function()
        install_show_stub()
        preview.setup()
        local custom = function(buf_id, items)
          vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.tbl_map(to_line, items))
        end
        local picker_opts = { source = { show = custom } }
        package.loaded['mini.pick'].get_picker_opts = function()
          return vim.deepcopy(picker_opts)
        end
        package.loaded['mini.pick'].set_picker_opts = function(opts)
          picker_opts = vim.tbl_deep_extend('force', picker_opts, opts)
        end
        vim.api.nvim_exec_autocmds('User', { pattern = 'MiniPickStart' })

        local bufnr = scratch({})
        picker_opts.source.show(bufnr, { grep_item(envfile, 'API_KEY=row-secret') }, {}, {})

        assert.is_table(row_marks(bufnr)[1])
      end)

      it('leaves rows alone when picker_results is off', function()
        install_show_stub()
        config.set('integrations.picker_results', false)
        preview.setup()
        require('camouflage.integrations.later').try_all()

        local bufnr = scratch({})
        require('mini.pick').default_show(
          bufnr,
          { grep_item(envfile, 'API_KEY=row-secret') },
          {},
          {}
        )

        assert.is_nil(row_marks(bufnr)[1])
        config.set('integrations.picker_results', true)
      end)

      it('covers the value in the preview window title', function()
        install_show_stub()
        local item = grep_item(envfile, 'API_KEY=title-secret')
        local win = vim.api.nvim_open_win(scratch({}), false, {
          relative = 'editor',
          row = 1,
          col = 1,
          width = 80,
          height = 3,
          border = 'single',
          title = { { ' ' .. to_line(item) .. ' ', 'Title' } },
        })
        package.loaded['mini.pick'].get_picker_state = function()
          return { windows = { main = win } }
        end
        preview.setup()
        require('camouflage.integrations.later').try_all()

        require('mini.pick').default_preview(scratch({}), item)

        assert.is_true(
          vim.wait(500, function()
            local title = vim.api.nvim_win_get_config(win).title[1][1]
            return not title:find('title-secret', 1, true)
              and title:find('API_KEY=', 1, true) ~= nil
          end, 10),
          'value still in the title'
        )
        vim.api.nvim_win_close(win, true)
      end)
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
