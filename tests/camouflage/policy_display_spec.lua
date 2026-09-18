-- A policy rule can carry how its values are masked, not just whether they are.
-- The fields are data (a style name and a few numbers), so a project file can
-- set them without anything executable.
describe('camouflage policy display fields', function()
  local core
  local config
  local styles
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

  ---The mask drawn over the value on a row.
  local function mask_on(bufnr, row)
    local state = require('camouflage.state')
    for _, mark in
      ipairs(vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, { row, 0 }, { row, -1 }, {
        details = true,
      }))
    do
      local details = mark[4]
      if details.virt_text then
        return details.virt_text[1][1]
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
    core = require('camouflage.core')
    config = require('camouflage.config')
    styles = require('camouflage.styles')
  end)

  after_each(function()
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
  end)

  describe('partial_text', function()
    it('keeps the last characters', function()
      assert.equals(
        '****************MPLE',
        styles.partial_text('AKIAIOSFODNN7EXAMPLE', { show_end = 4, mask_char = '*' })
      )
    end)

    it('keeps the first characters', function()
      assert.equals('se****', styles.partial_text('secret', { show_start = 2, mask_char = '*' }))
    end)

    it('counts characters, not bytes', function()
      assert.equals('şi***', styles.partial_text('şifre', { show_start = 2, mask_char = '*' }))
    end)

    it('covers everything when the visible ends would meet', function()
      assert.equals(
        '******',
        styles.partial_text('secret', { show_start = 4, show_end = 4, mask_char = '*' })
      )
    end)

    it('covers everything when nothing was asked for', function()
      assert.equals('******', styles.partial_text('secret', { mask_char = '*' }))
    end)
  end)

  describe('rules', function()
    it('uses the style of the rule that matched', function()
      config.set('policy.rules', {
        {
          id = 'aws-id',
          action = 'mask',
          key = { '^AWS_ACCESS_KEY_ID$' },
          style = 'partial',
          show_end = 4,
        },
      })
      local bufnr = open('display.env', {
        'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE',
        'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI',
      })

      assert.equals('****************MPLE', mask_on(bufnr, 0))
      -- The other value keeps the buffer's own style.
      assert.equals('*************', mask_on(bufnr, 1))
    end)

    it('uses the mask character and length of the rule', function()
      config.set('policy.rules', {
        {
          id = 'fixed',
          action = 'mask',
          key = { '^DB_PASSWORD$' },
          mask_char = '#',
          mask_length = 10,
        },
      })
      local bufnr = open('fixed.env', { 'DB_PASSWORD=Tr0ub4dor-and-more' })

      -- A shorter mask is padded with spaces, otherwise the tail of the value
      -- would show through the overlay. That padding is what hides the length.
      local mask = mask_on(bufnr, 0)
      assert.equals('##########', (mask:gsub('%s+$', '')))
      assert.equals(#'Tr0ub4dor-and-more', vim.fn.strdisplaywidth(mask))
    end)

    it('leaves values no rule matched on the buffer style', function()
      config.set('policy.rules', {
        { id = 'other', action = 'mask', key = { '^NOPE$' }, style = 'dotted' },
      })
      local bufnr = open('other.env', { 'API_KEY=plain-secret' })

      assert.equals('************', mask_on(bufnr, 0))
    end)

    it('ignores a rule whose style is not a style', function()
      config.set('policy.rules', {
        { id = 'bad', action = 'mask', key = { '^API_KEY$' }, style = 'invisible' },
      })
      local bufnr = open('bad.env', { 'API_KEY=plain-secret' })

      -- The rule is dropped, so the value is still masked the normal way.
      assert.equals('************', mask_on(bufnr, 0))
    end)

    it('ignores a rule whose numbers are not whole', function()
      config.set('policy.rules', {
        { id = 'bad', action = 'mask', key = { '^API_KEY$' }, style = 'partial', show_end = 2.5 },
      })
      local bufnr = open('bad2.env', { 'API_KEY=plain-secret' })

      assert.equals('************', mask_on(bufnr, 0))
    end)

    it('carries the fields on the decision, without the value', function()
      config.set('policy.rules', {
        {
          id = 'aws-id',
          action = 'mask',
          key = { '^API_KEY$' },
          style = 'partial',
          show_end = 3,
        },
      })
      local bufnr = open('decision.env', { 'API_KEY=plain-secret' })

      local var = require('camouflage.state').get_variables(bufnr)[1]
      assert.equals('aws-id', var.policy.rule_id)
      assert.same({ style = 'partial', show_end = 3 }, var.policy.display)
    end)
  end)
end)
