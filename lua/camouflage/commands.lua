---@mod camouflage.commands User commands

local M = {}

---Setup all user commands for camouflage
---@return nil
function M.setup()
  vim.api.nvim_create_user_command('CamouflageToggle', function()
    local camouflage = require('camouflage')
    camouflage.toggle()
    local status = camouflage.is_enabled() and 'enabled' or 'disabled'
    vim.notify('[camouflage] ' .. status, vim.log.levels.INFO)
  end, { desc = 'Toggle Camouflage' })

  vim.api.nvim_create_user_command('CamouflageRefresh', function()
    require('camouflage').refresh()
    vim.notify('[camouflage] refreshed', vim.log.levels.INFO)
  end, { desc = 'Refresh Camouflage decorations' })

  vim.api.nvim_create_user_command('CamouflageStatus', function()
    local camouflage = require('camouflage')
    local state = require('camouflage.state')
    local parsers = require('camouflage.parsers')

    local enabled = camouflage.is_enabled()
    local bufnr = vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local _, parser_name = parsers.find_parser_for_file(filename)
    local vars = state.get_variables(bufnr)

    local lines = {
      '[camouflage] Status:',
      '  Global: ' .. (enabled and 'enabled' or 'disabled'),
      '  Buffer: ' .. (state.is_buffer_masked(bufnr) and 'masked' or 'not masked'),
      '  Parser: ' .. (parser_name or 'none'),
      '  Masked values: ' .. #vars,
    }
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  end, { desc = 'Show Camouflage status' })

  vim.api.nvim_create_user_command('CamouflageYank', function(opts)
    local yank = require('camouflage.yank')
    yank.yank({
      force_picker = opts.bang,
      register = opts.args ~= '' and opts.args or nil,
    })
  end, {
    desc = 'Copy unmasked value to clipboard',
    bang = true,
    nargs = '?',
  })

  vim.api.nvim_create_user_command('CamouflageReveal', function(opts)
    local reveal = require('camouflage.reveal')
    if opts.bang then
      reveal.hide()
    else
      reveal.toggle()
    end
  end, {
    desc = 'Reveal masked values on current line',
    bang = true,
  })

  vim.api.nvim_create_user_command('CamouflageFollowCursor', function(opts)
    local reveal = require('camouflage.reveal')
    reveal.toggle_follow_cursor({
      force_disable = opts.bang,
    })
  end, {
    desc = 'Toggle follow cursor mode (auto-reveal current line)',
    bang = true,
  })

  -- Pwned password check commands
  vim.api.nvim_create_user_command('CamouflagePwnedCheck', function()
    require('camouflage.pwned').check_current()
  end, { desc = 'Check if value under cursor is pwned' })

  vim.api.nvim_create_user_command('CamouflagePwnedCheckLine', function()
    require('camouflage.pwned').check_line()
  end, { desc = 'Check all values on current line' })

  vim.api.nvim_create_user_command('CamouflagePwnedCheckBuffer', function()
    require('camouflage.pwned').check_buffer()
  end, { desc = 'Check all values in buffer' })

  vim.api.nvim_create_user_command('CamouflagePwnedClear', function()
    require('camouflage.pwned').clear()
  end, { desc = 'Clear pwned indicators from buffer' })

  vim.api.nvim_create_user_command('CamouflagePwnedClearCache', function()
    require('camouflage.pwned').clear_cache()
  end, { desc = 'Clear pwned check cache' })
end

return M
