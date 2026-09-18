---@mod lualine.components.camouflage Lualine component

local M = require('lualine.component'):extend()

M.default_options = {
  -- Nerd Font eye-slash (values hidden) and eye (values visible)
  icon_enabled = '',
  icon_disabled = '',
  show_disabled = false,
  show_count = false,
  show_follow_indicator = true,
  follow_indicator = '[F]',
  show_present_indicator = true,
  present_indicator = '[P]',
}

function M:init(options)
  M.super.init(self, options)
  self.options = vim.tbl_deep_extend('force', M.default_options, self.options or {})
end

function M:update_status()
  local ok = pcall(require, 'camouflage')
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

  -- Buffer-aware: vim.b.camouflage_enabled and the buffer's project config can
  -- turn masking off for this buffer while it's on globally.
  if require('camouflage.config').is_enabled_for_buffer(0) then
    local result = self.options.icon_enabled

    -- Add count
    if self.options.show_count then
      local state_ok, state = pcall(require, 'camouflage.state')
      if state_ok then
        local vars = state.get_variables(vim.api.nvim_get_current_buf())
        if #vars > 0 then
          result = result .. ' ' .. #vars
        end
      end
    end

    -- Presentation mode is the one state worth knowing at a glance: it is what
    -- you check before you start sharing the screen.
    if self.options.show_present_indicator then
      local present_ok, present = pcall(require, 'camouflage.present')
      if present_ok and present.is_active() then
        result = result .. ' ' .. self.options.present_indicator
      end
    end

    -- Add follow cursor indicator
    if self.options.show_follow_indicator then
      local reveal_ok, reveal = pcall(require, 'camouflage.reveal')
      if reveal_ok and reveal.is_follow_cursor_enabled() then
        result = result .. ' ' .. self.options.follow_indicator
      end
    end

    return result
  elseif self.options.show_disabled then
    return self.options.icon_disabled
  end

  return ''
end

return M
