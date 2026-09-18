-- `yy` on a masked line copies the real text, and `:registers` prints it. That
-- list is message output, so there is nothing to draw over: this prints the
-- same table with the masked values replaced.
describe('camouflage.registers', function()
  local registers
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
    require('camouflage.core').apply_decorations(bufnr)
    return bufnr
  end

  local function row_for(name)
    for _, line in ipairs(registers.lines()) do
      if line:find('"' .. name, 1, true) then
        return line
      end
    end
    return nil
  end

  before_each(function()
    clear_modules()
    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
    })
    registers = require('camouflage.registers')
    for _, name in ipairs({ 'a', 'b', 'c', '"', '0' }) do
      vim.fn.setreg(name, '')
    end
  end)

  after_each(function()
    for _, name in ipairs({ 'a', 'b', 'c', '"', '0' }) do
      vim.fn.setreg(name, '')
    end
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
  end)

  it('replaces a register holding a masked value', function()
    open('reg.env', { 'API_KEY=register-secret' })
    vim.fn.setreg('a', 'register-secret')

    local row = row_for('a')
    assert.is_not_nil(row)
    assert.is_nil(row:find('register-secret', 1, true))
    assert.is_not_nil(row:find('masked', 1, true))
  end)

  it('replaces a whole line yanked from a masked buffer', function()
    open('line.env', { 'API_KEY=register-secret' })
    vim.fn.setreg('a', 'API_KEY=register-secret\n', 'l')

    local row = row_for('a')
    assert.is_nil(row:find('register-secret', 1, true))
  end)

  it('leaves ordinary registers as they are', function()
    open('other.env', { 'API_KEY=register-secret' })
    vim.fn.setreg('b', 'just a note')

    local row = row_for('b')
    assert.is_not_nil(row:find('just a note', 1, true))
  end)

  it('shows newlines without breaking the row', function()
    vim.fn.setreg('b', 'first\nsecond')

    local row = row_for('b')
    assert.is_not_nil(row:find('first^Jsecond', 1, true))
  end)

  it('skips empty registers', function()
    vim.fn.setreg('c', '')
    assert.is_nil(row_for('c'))
  end)

  it('has nothing to redact when no buffer is masked', function()
    vim.fn.setreg('a', 'register-secret')

    local row = row_for('a')
    assert.is_not_nil(row:find('register-secret', 1, true))
  end)

  describe('holds_secret', function()
    it('matches the value itself and a line containing it', function()
      local values = { ['register-secret'] = true }

      assert.is_true(registers.holds_secret('register-secret', values))
      assert.is_true(registers.holds_secret('API_KEY=register-secret\n', values))
      assert.is_false(registers.holds_secret('something else', values))
      assert.is_false(registers.holds_secret('', values))
    end)

    it('does not match on a very short value, which would hit everything', function()
      assert.is_false(registers.holds_secret('a longer piece of text', { ['ext'] = true }))
    end)
  end)

  it('collects the values of every masked buffer', function()
    open('one.env', { 'API_KEY=first-secret' })
    open('two.env', { 'API_KEY=second-secret' })

    local values = registers.masked_values()
    assert.is_true(values['first-secret'])
    assert.is_true(values['second-secret'])
  end)
end)
