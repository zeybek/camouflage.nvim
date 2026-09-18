-- A quickfix row shows the matched line of the file it points at, so rows from
-- a supported file get the value covered while the list is drawn. The list
-- itself keeps the real text.
describe('camouflage.integrations.quickfix', function()
  local quickfix
  local config
  local dir
  local env_file
  local lua_file

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  ---Row as the list draws it, with the item it was drawn from.
  local function row(winid, index)
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local line = vim.api.nvim_buf_get_lines(bufnr, index, index + 1, false)[1]
    local items = quickfix.list_items(winid) or {}
    return line, items[index + 1]
  end

  ---What the mask would cover on a row, as text.
  local function covered(winid, index)
    local line, item = row(winid, index)
    local col, value = quickfix.row_value(line, item)
    if not col then
      return nil
    end
    assert.equals(value, line:sub(col + 1, col + #value))
    return value
  end

  local function open_list(items, loclist)
    if loclist then
      vim.fn.setloclist(0, items)
      vim.cmd('lopen')
    else
      vim.fn.setqflist(items)
      vim.cmd('copen')
    end
    return vim.api.nvim_get_current_win()
  end

  before_each(function()
    clear_modules()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    env_file = dir .. '/.env'
    lua_file = dir .. '/config.lua'
    vim.fn.writefile({ 'API_KEY=quickfix-secret', 'DEBUG=true' }, env_file)
    vim.fn.writefile({ 'local api_key = "in-source-code"' }, lua_file)

    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
    })
    config = require('camouflage.config')
    quickfix = require('camouflage.integrations.quickfix')
    quickfix._reset()
  end)

  after_each(function()
    pcall(vim.cmd, 'cclose')
    pcall(vim.cmd, 'lclose')
    vim.fn.setqflist({})
    vim.fn.delete(dir, 'rf')
  end)

  it('covers the value on rows from a supported file', function()
    local winid = open_list({
      { filename = env_file, lnum = 1, col = 1, text = 'API_KEY=quickfix-secret' },
      { filename = env_file, lnum = 2, col = 1, text = 'DEBUG=true' },
    })

    assert.equals('quickfix-secret', covered(winid, 0))
    assert.equals('true', covered(winid, 1))
  end)

  it('leaves rows from other files alone', function()
    local winid = open_list({
      { filename = lua_file, lnum = 1, col = 1, text = 'local api_key = "in-source-code"' },
    })

    assert.is_nil(covered(winid, 0))
  end)

  it('reads a location list from its own window', function()
    local winid = open_list({
      { filename = env_file, lnum = 1, col = 1, text = 'API_KEY=quickfix-secret' },
    }, true)

    assert.equals('quickfix-secret', covered(winid, 0))
  end)

  it('follows the list that is on screen right now', function()
    local winid = open_list({
      { filename = env_file, lnum = 2, col = 1, text = 'DEBUG=true' },
    })
    assert.equals('true', covered(winid, 0))

    -- Nothing to hook: the rows are read again on the next draw.
    vim.fn.setqflist({
      { filename = env_file, lnum = 1, col = 1, text = 'API_KEY=quickfix-secret' },
    })

    assert.equals('quickfix-secret', covered(winid, 0))
  end)

  it('keeps the real text in the list', function()
    open_list({
      { filename = env_file, lnum = 1, col = 1, text = 'API_KEY=quickfix-secret' },
    })

    assert.equals('API_KEY=quickfix-secret', vim.fn.getqflist()[1].text)
  end)

  describe('on_win', function()
    it('takes quickfix windows with items in them', function()
      local winid = open_list({
        { filename = env_file, lnum = 1, col = 1, text = 'API_KEY=quickfix-secret' },
      })

      assert.is_true(quickfix.on_win(winid, vim.api.nvim_win_get_buf(winid)))
    end)

    it('skips windows that are not a list', function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_set_current_buf(bufnr)

      assert.is_false(quickfix.on_win(vim.api.nvim_get_current_win(), bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('skips an empty list', function()
      vim.fn.setqflist({})
      vim.cmd('copen')
      local winid = vim.api.nvim_get_current_win()

      assert.is_false(quickfix.on_win(winid, vim.api.nvim_win_get_buf(winid)))
    end)

    it('skips while the integration is off', function()
      config.set('integrations.quickfix', false)
      local winid = open_list({
        { filename = env_file, lnum = 1, col = 1, text = 'API_KEY=quickfix-secret' },
      })

      assert.is_false(quickfix.on_win(winid, vim.api.nvim_win_get_buf(winid)))
      config.set('integrations.quickfix', true)
    end)

    it('skips while masking is off', function()
      config.set('enabled', false)
      local winid = open_list({
        { filename = env_file, lnum = 1, col = 1, text = 'API_KEY=quickfix-secret' },
      })

      assert.is_false(quickfix.on_win(winid, vim.api.nvim_win_get_buf(winid)))
      config.set('enabled', true)
    end)
  end)
end)
