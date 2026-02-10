---@mod lualine.components.camouflage Lualine component

local M = require('lualine.component'):extend()

M.default_options = {
  icon_enabled = '',
  icon_disabled = '',
  show_disabled = false,
  show_count = false,
}

function M:init(options)
  M.super.init(self, options)
  self.options = vim.tbl_deep_extend('force', M.default_options, self.options or {})
end

function M:update_status()
  local ok, camouflage = pcall(require, 'camouflage')
  if not ok then
    return ''
  end

  local parsers_ok, parsers = pcall(require, 'camouflage.parsers')
  if not parsers_ok then
    return ''
  end

  local filename = vim.api.nvim_buf_get_name(0)
  if not parsers.is_supported(filename) then
    return ''
  end

  if camouflage.is_enabled() then
    if self.options.show_count then
      local state_ok, state = pcall(require, 'camouflage.state')
      if state_ok then
        local vars = state.get_variables(vim.api.nvim_get_current_buf())
        if #vars > 0 then
          return self.options.icon_enabled .. ' ' .. #vars
        end
      end
    end
    return self.options.icon_enabled
  elseif self.options.show_disabled then
    return self.options.icon_disabled
  end

  return ''
end

return M
