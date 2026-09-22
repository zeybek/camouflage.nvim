---@mod camouflage.integrations.terminal Mask values printed in a terminal

-- The file is masked, the terminal next to it is not. `env`, `printenv`, a
-- failed curl echoing its headers, a test runner dumping its config: all of
-- them put real values on screen in the same window layout.
--
-- There is no file here, so there is no parser and no key structure to rely on.
-- All this has is the shape of a line, which is why it is off by default and
-- limited to keys that already look sensitive. `keys = 'all'` widens it to any
-- `KEY=value`, which is louder but hides more.
--
-- Drawn from a decoration provider, so scrollback and a command printing
-- thousands of lines cost only what is on screen.

local M = {}

local config = require('camouflage.config')
local linemask = require('camouflage.linemask')
local styles = require('camouflage.styles')

M.namespace = vim.api.nvim_create_namespace('camouflage_terminal')

---@type table|nil
local current

---@param cfg table
---@return string
local function highlight_group(cfg)
  return cfg.colors and 'CamouflageMask' or cfg.highlight_group
end

---@return table
local function terminal_config()
  return config.get().terminal or {}
end

---Key patterns that mark a line as worth covering.
---@return string[]
function M.sensitive_patterns()
  local terminal = terminal_config()
  if terminal.key_patterns then
    return terminal.key_patterns
  end
  local checks = config.get().checks or {}
  local weak = checks.weak_secret or {}
  return weak.sensitive_key_patterns or {}
end

-- A value of the shape `scheme://user:password@host`. The password rides in
-- the value here, so the key it was printed under says nothing about it.
local CREDENTIAL_URL = '%a[%w+.%-]*://[^:/?#%s]+:[^@/?#%s]+@'

---What can sit in front of the key on a printed line: a comment marker and a
---shell `export`. The line-level matcher already reads past both, so a key
---behind one is a key all the same.
---@param line string
---@return string
local function without_prefix(line)
  local rest = line:gsub('^%s*[#;]+%s*', '')
  rest = rest:gsub('^%s*export%s+', '')
  return (require('camouflage.parsers.util').strip_shell_declaration(rest))
end

---The key on a line, if it reads like `KEY=value` or `KEY: value`.
---@param line string
---@return string|nil
function M.line_key(line)
  local rest = without_prefix(line)
  return rest:match('^%s*["\']?([%w_.%-]+)["\']?%s*[=:]')
    or rest:match('^%s*[Ee][Nn][Vv]%s+([%w_]+)%s*[=%s]')
end

---Whether the value on a line carries credentials of its own, whatever the key
---it was printed under is called.
---@param line string
---@return boolean
function M.holds_credentials(line)
  local _, value = linemask.find_value(line)
  return value ~= nil and value:find(CREDENTIAL_URL) ~= nil
end

---Whether a line should be covered at all.
---@param line string
---@return boolean
function M.should_mask(line)
  if M.holds_credentials(line) then
    return true
  end
  local key = M.line_key(line)
  if not key then
    return false
  end
  if terminal_config().keys == 'all' then
    return true
  end
  local lowered = key:lower()
  for _, pattern in ipairs(M.sensitive_patterns()) do
    local ok, matched = pcall(string.find, lowered, pattern)
    if ok and matched then
      return true
    end
  end
  return false
end

---@return boolean
local function enabled()
  local cfg = config.get()
  return cfg.enabled and (cfg.terminal or {}).enabled == true
end

---Picks up the state a terminal window's rows are drawn with. Public so it can
---be tested without a redraw.
---@param bufnr number
---@return boolean
function M.on_win(bufnr)
  current = nil
  if not enabled() or vim.bo[bufnr].buftype ~= 'terminal' then
    return false
  end
  if vim.b[bufnr].camouflage_terminal == false then
    return false
  end
  current = { cfg = config.get() }
  return true
end

---Masks one row while the window is drawn. Returns what it covered.
---@param bufnr number
---@param row number
---@return number|nil col
---@return string|nil value
function M.on_line(bufnr, row)
  if not current then
    return nil, nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line or not M.should_mask(line) then
    return nil, nil
  end

  local col, value = linemask.find_value(line)
  if not col or not value then
    return nil, nil
  end

  local cfg = current.cfg
  pcall(vim.api.nvim_buf_set_extmark, bufnr, M.namespace, row, col, {
    end_col = col + #value,
    virt_text = {
      {
        styles.generate_hidden_text(cfg.style, vim.fn.strdisplaywidth(value), value, cfg),
        highlight_group(cfg),
      },
    },
    virt_text_pos = 'overlay',
    hl_mode = 'combine',
    ephemeral = true,
  })
  return col, value
end

---@return nil
function M.setup()
  vim.api.nvim_set_decoration_provider(M.namespace, {
    on_win = function(_, _, bufnr)
      return M.on_win(bufnr)
    end,
    on_line = function(_, _, bufnr, row)
      M.on_line(bufnr, row)
    end,
  })
end

---Internal: drop the per-redraw state (used by tests).
---@return nil
function M._reset()
  current = nil
end

return M
