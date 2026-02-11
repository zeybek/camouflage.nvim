-- Pwned feature requires Neovim 0.10+ (vim.system)
if vim.fn.has('nvim-0.10') == 0 then
  describe('camouflage.pwned.ui (skipped)', function()
    it('requires Neovim 0.10+', function()
      pending('Pwned feature requires Neovim 0.10+')
    end)
  end)
  return
end

describe('camouflage.pwned.ui', function()
  local ui

  before_each(function()
    ui = require('camouflage.pwned.ui')
  end)

  describe('setup_highlights', function()
    it('should create highlight groups', function()
      ui.setup_highlights()
      -- Check that highlight groups exist
      local hl = vim.api.nvim_get_hl(0, { name = 'CamouflagePwned' })
      assert.is_table(hl)
    end)
  end)

  describe('format_count', function()
    it('should format millions', function()
      assert.equals('9.5M', ui.format_count(9500000))
      assert.equals('1.0M', ui.format_count(1000000))
    end)

    it('should format thousands', function()
      assert.equals('152K', ui.format_count(152000))
      assert.equals('2K', ui.format_count(1500))
    end)

    it('should format small numbers as-is', function()
      assert.equals('999', ui.format_count(999))
      assert.equals('1', ui.format_count(1))
    end)
  end)

  describe('get_namespace', function()
    it('should return a valid namespace id', function()
      local ns = ui.get_namespace()
      assert.is_number(ns)
      assert.is_true(ns > 0)
    end)
  end)

  describe('mark_pwned', function()
    it('should add extmarks to buffer', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'PASSWORD=secret123' })

      local config = {
        show_sign = true,
        show_virtual_text = true,
        show_line_highlight = true,
        sign_text = '!',
        sign_hl = 'DiagnosticWarn',
        virtual_text_prefix = ' PWNED: ',
        virtual_text_hl = 'DiagnosticWarn',
        line_hl = 'CamouflagePwned',
      }

      ui.mark_pwned(bufnr, 0, 1000000, config)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ui.get_namespace(), 0, -1, {})
      assert.is_true(#extmarks > 0)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('clear_marks', function()
    it('should remove all extmarks from buffer', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'PASSWORD=secret123' })

      local config = {
        show_sign = true,
        show_virtual_text = true,
        show_line_highlight = true,
        sign_text = '!',
        sign_hl = 'DiagnosticWarn',
        virtual_text_prefix = ' PWNED: ',
        virtual_text_hl = 'DiagnosticWarn',
        line_hl = 'CamouflagePwned',
      }

      ui.mark_pwned(bufnr, 0, 1000, config)
      ui.clear_marks(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ui.get_namespace(), 0, -1, {})
      assert.equals(0, #extmarks)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
