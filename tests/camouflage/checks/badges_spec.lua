local checks = require('camouflage.checks')
local badges = require('camouflage.checks.badges')
local store = require('camouflage.checks.store')

local function fresh_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { 'foo', 'bar', 'baz' })
  return bufnr
end

local function get_mark(bufnr, lnum)
  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    badges.get_namespace(),
    { lnum, 0 },
    { lnum, -1 },
    { details = true }
  )
  return marks[1]
end

describe('camouflage.checks.badges', function()
  before_each(function()
    store._reset()
  end)

  it('renders nothing when no result exists', function()
    local bufnr = fresh_buffer()
    badges.render(bufnr, 0)
    assert.is_nil(get_mark(bufnr, 0))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('renders a single check as one virt_text chunk', function()
    local bufnr = fresh_buffer()
    checks.set_result(bufnr, 0, 'pwned', {
      severity = 'error',
      text = 'PWNED 5x',
      hl_group = 'CamouflagePwnedVirtualText',
      sign_text = '!',
      sign_hl = 'CamouflagePwnedSign',
      line_hl = 'CamouflagePwned',
    })
    local mark = get_mark(bufnr, 0)
    assert.is_table(mark)
    assert.same({ { 'PWNED 5x', 'CamouflagePwnedVirtualText' } }, mark[4].virt_text)
    -- Neovim pads single-char sign_text to width 2
    assert.equals('!', vim.trim(mark[4].sign_text))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('composes multiple checks with a separator chunk between them', function()
    local bufnr = fresh_buffer()
    checks.set_result(bufnr, 0, 'pwned', {
      severity = 'error',
      text = '[PWNED]',
      hl_group = 'DiagnosticError',
      sign_text = '!',
      sign_hl = 'DiagnosticError',
    })
    checks.set_result(bufnr, 0, 'expiry', {
      severity = 'warning',
      text = '[expires 2h]',
      hl_group = 'DiagnosticWarn',
    })
    checks.set_result(bufnr, 0, 'weak_secret', {
      severity = 'warning',
      text = '[weak: short]',
      hl_group = 'DiagnosticWarn',
    })
    local mark = get_mark(bufnr, 0)
    -- order: pwned, weak_secret, expiry
    assert.equals(5, #mark[4].virt_text)
    assert.equals('[PWNED]', mark[4].virt_text[1][1])
    assert.equals(' ', mark[4].virt_text[2][1])
    assert.equals('[weak: short]', mark[4].virt_text[3][1])
    assert.equals(' ', mark[4].virt_text[4][1])
    assert.equals('[expires 2h]', mark[4].virt_text[5][1])
    -- pwned has higher severity -> its sign wins
    -- Neovim pads single-char sign_text to width 2
    assert.equals('!', vim.trim(mark[4].sign_text))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('higher-severity check wins sign + line_hl', function()
    local bufnr = fresh_buffer()
    checks.set_result(bufnr, 0, 'expiry', {
      severity = 'warning',
      text = '[expires]',
      sign_text = 'W',
      sign_hl = 'DiagnosticWarn',
      line_hl = 'WarningLine',
    })
    checks.set_result(bufnr, 0, 'pwned', {
      severity = 'error',
      text = '[PWNED]',
      sign_text = '!',
      sign_hl = 'DiagnosticError',
      line_hl = 'CamouflagePwned',
    })
    local mark = get_mark(bufnr, 0)
    -- Neovim pads single-char sign_text to width 2
    assert.equals('!', vim.trim(mark[4].sign_text))
    assert.equals('CamouflagePwned', mark[4].line_hl_group)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('clearing a check removes its virt_text chunk', function()
    local bufnr = fresh_buffer()
    checks.set_result(bufnr, 0, 'pwned', { severity = 'error', text = 'P' })
    checks.set_result(bufnr, 0, 'expiry', { severity = 'info', text = 'E' })
    checks.set_result(bufnr, 0, 'expiry', nil)
    local mark = get_mark(bufnr, 0)
    assert.equals(1, #mark[4].virt_text)
    assert.equals('P', mark[4].virt_text[1][1])
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('clear_check removes badges for all lines of that check', function()
    local bufnr = fresh_buffer()
    checks.set_result(bufnr, 0, 'pwned', { severity = 'error', text = 'a' })
    checks.set_result(bufnr, 1, 'pwned', { severity = 'error', text = 'b' })
    checks.set_result(bufnr, 1, 'expiry', { severity = 'info', text = 'c' })
    checks.clear_check(bufnr, 'pwned')
    assert.is_nil(get_mark(bufnr, 0))
    -- line 1 should still have expiry badge
    local mark = get_mark(bufnr, 1)
    assert.is_table(mark)
    assert.equals('c', mark[4].virt_text[1][1])
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('clear_buffer removes all marks', function()
    local bufnr = fresh_buffer()
    checks.set_result(bufnr, 0, 'pwned', { severity = 'error', text = 'a' })
    checks.set_result(bufnr, 1, 'expiry', { severity = 'info', text = 'b' })
    checks.clear_buffer(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, badges.get_namespace(), 0, -1, {})
    assert.equals(0, #marks)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('re-rendering a line is idempotent (deterministic id, no duplicates)', function()
    local bufnr = fresh_buffer()
    checks.set_result(bufnr, 0, 'pwned', { severity = 'error', text = 'P' })
    badges.render(bufnr, 0)
    badges.render(bufnr, 0)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, badges.get_namespace(), 0, -1, {})
    assert.equals(1, #marks)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('renders distinct lines as distinct marks', function()
    local bufnr = fresh_buffer()
    checks.set_result(bufnr, 0, 'pwned', { severity = 'error', text = 'a' })
    checks.set_result(bufnr, 2, 'pwned', { severity = 'error', text = 'b' })
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, badges.get_namespace(), 0, -1, {})
    assert.equals(2, #marks)
    assert.is_table(get_mark(bufnr, 0))
    assert.is_table(get_mark(bufnr, 2))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
