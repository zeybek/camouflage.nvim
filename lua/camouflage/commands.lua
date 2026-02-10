---@mod camouflage.commands User commands

local M = {}

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
end

return M
