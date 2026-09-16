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

  describe('when lines move', function()
    local function badge_text(bufnr, lnum)
      local mark = get_mark(bufnr, lnum)
      if not mark or not mark[4].virt_text then
        return nil
      end
      local parts = {}
      for _, chunk in ipairs(mark[4].virt_text) do
        table.insert(parts, chunk[1])
      end
      return table.concat(parts)
    end

    it('moves a result with its line when lines are inserted above', function()
      local bufnr = fresh_buffer({ 'a', 'b', 'c' })
      checks.set_result(bufnr, 1, 'pwned', { severity = 'error', text = 'PWNED' })

      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { 'new first line' })
      checks.render_buffer(bufnr)

      assert.is_nil(store.get(bufnr, 1, 'pwned'))
      assert.is_table(store.get(bufnr, 2, 'pwned'))
      assert.equals('PWNED', badge_text(bufnr, 2))
      assert.is_nil(badge_text(bufnr, 1))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('keeps each badge on its own line after a shift', function()
      local bufnr = fresh_buffer({ 'a', 'b', 'c' })
      checks.set_result(bufnr, 0, 'pwned', { severity = 'error', text = 'FIRST' })
      checks.set_result(bufnr, 2, 'pwned', { severity = 'error', text = 'THIRD' })

      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { 'new first line' })
      checks.render_buffer(bufnr)

      assert.equals('FIRST', badge_text(bufnr, 1))
      assert.equals('THIRD', badge_text(bufnr, 3))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    if vim.fn.has('nvim-0.10') == 1 then
      it('drops a result when its line is deleted', function()
        local bufnr = fresh_buffer({ 'a', 'secret line', 'c' })
        checks.set_result(bufnr, 1, 'pwned', { severity = 'error', text = 'PWNED' })

        vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, {})
        checks.render_buffer(bufnr)

        assert.same({}, store.lines_with_results(bufnr))
        assert.is_nil(badge_text(bufnr, 1))
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)
    end

    it('keeps the PWNED badge on its value when weak_secret redecorates', function()
      require('camouflage').setup({ project_config = { enabled = false } })
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '/badge.env')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'A=1', 'PASSWORD=hunter2', 'C=3' })
      local core = require('camouflage.core')
      core.apply_decorations(bufnr)
      require('camouflage.pwned.ui').mark_pwned(bufnr, 1, 100)

      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '# new top line' })
      core.apply_decorations(bufnr)

      local pwned_line
      for lnum = 0, vim.api.nvim_buf_line_count(bufnr) - 1 do
        local text = badge_text(bufnr, lnum)
        if text and text:find('PWNED', 1, true) then
          pwned_line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
        end
      end
      vim.api.nvim_buf_delete(bufnr, { force = true })

      assert.equals('PASSWORD=hunter2', pwned_line)
    end)
  end)
end)
