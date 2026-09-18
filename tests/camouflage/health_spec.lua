-- `:checkhealth camouflage` answers "why is nothing masked" without reading the
-- source, so the report has to name the reason and never print a value.
describe('camouflage.health', function()
  local health
  local report
  local originals = {}
  local buffers = {}

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  ---Collect what the report says instead of writing it to a buffer.
  local function capture()
    report = { start = {}, ok = {}, warn = {}, info = {}, all = {} }
    local h = vim.health
    for _, name in ipairs({ 'start', 'ok', 'warn', 'info' }) do
      local key = h[name] and name or ('report_' .. name)
      originals[key] = h[key]
      h[key] = function(msg, ...)
        table.insert(report[name], msg)
        table.insert(report.all, msg)
        local advice = select(1, ...)
        if type(advice) == 'table' then
          for _, line in ipairs(advice) do
            table.insert(report.all, line)
          end
        end
      end
    end
  end

  local function restore()
    for key, fn in pairs(originals) do
      vim.health[key] = fn
    end
    originals = {}
  end

  local function said(pattern)
    for _, line in ipairs(report.all) do
      if type(line) == 'string' and line:lower():find(pattern:lower(), 1, true) then
        return line
      end
    end
    return nil
  end

  local function open(name, lines)
    local bufnr = vim.api.nvim_create_buf(true, false)
    table.insert(buffers, bufnr)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '/' .. name)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  before_each(function()
    clear_modules()
    capture()
  end)

  after_each(function()
    restore()
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
  end)

  it('says so when setup never ran', function()
    health = require('camouflage.health')
    health.check()

    assert.is_not_nil(said('setup() has not run'))
    assert.is_nil(said('Parsers'))
  end)

  describe('after setup', function()
    before_each(function()
      require('camouflage').setup({
        project_config = { enabled = false, watch_enabled = false },
        reveal = { notify = false },
      })
      health = require('camouflage.health')
    end)

    it('reports the registered parsers', function()
      health.check()

      local line = said('parsers:')
      assert.is_not_nil(line)
      assert.is_not_nil(line:find('env', 1, true))
      assert.is_not_nil(line:find('json', 1, true))
    end)

    it('reports the parser and the masked count of the buffer in the window', function()
      open('health.env', { 'API_KEY=health-secret', 'DEBUG=true' })
      require('camouflage.core').apply_decorations(vim.api.nvim_get_current_buf())

      health.check()

      assert.is_not_nil(said('is handled by the env parser'))
      assert.is_not_nil(said('2 values are masked'))
    end)

    it('never prints a value', function()
      open('health.env', { 'API_KEY=health-secret' })
      require('camouflage.core').apply_decorations(vim.api.nvim_get_current_buf())

      health.check()

      assert.is_nil(said('health-secret'))
    end)

    it('says when no parser handles the buffer', function()
      open('notes.txt', { 'nothing to see' })

      health.check()

      assert.is_not_nil(said('no parser handles'))
    end)

    it('says when masking is off for the buffer', function()
      local bufnr = open('off.env', { 'API_KEY=health-secret' })
      vim.b[bufnr].camouflage_enabled = false

      health.check()

      assert.is_not_nil(said('masking is off for this buffer'))
    end)

    it('says when masking is off everywhere', function()
      local config = require('camouflage.config')
      config.set('enabled', false)

      health.check()

      assert.is_not_nil(said('masking is off'))
      config.set('enabled', true)
    end)

    it('reports which surfaces beyond the file are masked', function()
      health.check()

      local line = said('masked beyond the file itself')
      assert.is_not_nil(line)
      assert.is_not_nil(line:find('quickfix', 1, true))
    end)

    it('reports the offline checks that are on', function()
      health.check()

      local line = said('offline checks:')
      assert.is_not_nil(line)
      assert.is_not_nil(line:find('weak_secret', 1, true))
    end)

    it('reports missing treesitter grammars as advice, not a failure', function()
      health.check()

      -- Either they are installed or the report tells you how to install them.
      assert.is_true(said('grammars installed') ~= nil or said('no grammar for') ~= nil)
      assert.is_nil(said('ERROR'))
    end)
  end)
end)
