---@mod camouflage.present Presentation mode

-- Before a demo there are several switches to remember: masking on, follow
-- cursor off, no line left revealed, the terminal masker on, and that one
-- buffer where masking was turned off earlier. Missing one of them is the whole
-- problem, so this is one command that puts the session into a known state and
-- one that puts it back.

local M = {}

local config = require('camouflage.config')
local state = require('camouflage.state')

---@type table|nil
local saved

---@return boolean
function M.is_active()
  return saved ~= nil
end

---Buffer-local overrides that would keep a buffer readable.
---@return table[]
local function clear_buffer_overrides()
  local cleared = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].camouflage_enabled == false then
      table.insert(cleared, bufnr)
      vim.b[bufnr].camouflage_enabled = nil
    end
  end
  return cleared
end

---Turn presentation mode on. Everything it changes is remembered so `stop`
---can put it back.
---@return boolean started false when it was already on
function M.start()
  if saved then
    return false
  end

  local reveal = require('camouflage.reveal')
  local cfg = config.get()

  saved = {
    enabled = cfg.enabled,
    runtime_enabled = config.runtime_enabled,
    terminal_enabled = (cfg.terminal or {}).enabled,
    follow_cursor = reveal.is_follow_cursor_enabled(),
    buffers = clear_buffer_overrides(),
  }

  if reveal.is_follow_cursor_enabled() then
    reveal.stop_follow_cursor()
  end
  if reveal.is_revealed() then
    reveal.hide()
  end

  -- Always, not only when the global value is off: a buffer from another
  -- repository has a config of its own, and only the runtime value reaches
  -- it. Its project file may say `enabled: false`.
  config.set('enabled', true)
  -- Drop the per-project configs cached before, and make every buffer's last
  -- pass out of date, so a hidden buffer is decorated again when it is shown.
  config.clear_project_cache()
  if (cfg.terminal or {}).enabled ~= true then
    config.set('terminal.enabled', true)
    require('camouflage.integrations.terminal').setup()
  end

  require('camouflage.core').refresh_all()
  return true
end

---Turn it off and put back what was there before.
---@return boolean stopped false when it was not on
function M.stop()
  if not saved then
    return false
  end
  local previous = saved
  saved = nil

  if config.get().enabled ~= previous.enabled then
    config.set('enabled', previous.enabled)
  end
  -- Give other repositories their own `enabled` back.
  config.runtime_enabled = previous.runtime_enabled
  config.clear_project_cache()
  if (config.get().terminal or {}).enabled ~= previous.terminal_enabled then
    config.set('terminal.enabled', previous.terminal_enabled)
  end

  for _, bufnr in ipairs(previous.buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.b[bufnr].camouflage_enabled = false
    end
  end

  if previous.follow_cursor then
    require('camouflage.reveal').start_follow_cursor()
  end

  require('camouflage.core').refresh_all()
  return true
end

---@return boolean active
function M.toggle()
  if saved then
    M.stop()
    return false
  end
  M.start()
  return true
end

---Reveal commands refuse while presentation mode is on: the point of the mode
---is that nothing on screen can be uncovered by a keystroke.
---@return boolean blocked
function M.block_reveal()
  if not saved then
    return false
  end
  vim.notify(
    '[camouflage] presentation mode is on, run :CamouflagePresent! to leave it',
    vim.log.levels.WARN
  )
  return true
end

---Internal: forget the saved state (used by tests).
---@return nil
function M._reset()
  saved = nil
end

---@return string
function M.status()
  if not saved then
    return 'off'
  end
  local masked = 0
  for bufnr in pairs(state.buffers) do
    if state.is_buffer_masked(bufnr) then
      masked = masked + 1
    end
  end
  return ('on, %d masked buffer%s'):format(masked, masked == 1 and '' or 's')
end

return M
