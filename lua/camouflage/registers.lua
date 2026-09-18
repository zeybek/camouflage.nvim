---@mod camouflage.registers Redacted register listing

-- `yy` on a masked line copies the real text, which is why `:CamouflageYank`
-- exists. The value is in the register either way, and `:registers` prints
-- every register's contents, so one `:reg` puts a secret on screen in a list
-- that stays until a key is pressed.
--
-- That list is message output, not a buffer, so there is no extmark to draw
-- over it. This prints the same table with the contents of any register that
-- holds a masked value replaced.

local M = {}

local config = require('camouflage.config')
local state = require('camouflage.state')

-- Order Vim lists them in, minus the ones that can't hold a yanked value.
local NAMED = 'abcdefghijklmnopqrstuvwxyz'
local NUMBERED = '0123456789'
local SPECIAL = { '"', '-', '*', '+', '.', ':', '%', '/' }

---Every value masked in a loaded buffer right now.
---@return table<string, boolean>
function M.masked_values()
  local values = {}
  for bufnr, _ in pairs(state.buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      for _, var in ipairs(state.get_variables(bufnr)) do
        if type(var.value) == 'string' and var.value ~= '' then
          values[var.value] = true
        end
      end
    end
  end
  return values
end

---Whether a register's contents hold a value that is masked somewhere.
---@param contents string
---@param values table<string, boolean>
---@return boolean
function M.holds_secret(contents, values)
  if contents == '' then
    return false
  end
  if values[contents] then
    return true
  end
  for value, _ in pairs(values) do
    -- A linewise yank keeps the whole line, so the value sits inside it.
    if #value > 3 and contents:find(value, 1, true) then
      return true
    end
  end
  return false
end

---@param name string
---@return string
local function register_type(name)
  local ok, kind = pcall(vim.fn.getregtype, name)
  if not ok or kind == '' then
    return 'c'
  end
  return kind:sub(1, 1)
end

---The rows `:CamouflageRegisters` prints.
---@return string[]
function M.lines()
  local values = M.masked_values()
  local cfg = config.get()
  local placeholder = ('%s (masked)'):format(string.rep(cfg.mask_char or '*', 8))

  local names = {}
  for _, name in ipairs(SPECIAL) do
    table.insert(names, name)
  end
  for i = 1, #NUMBERED do
    table.insert(names, NUMBERED:sub(i, i))
  end
  for i = 1, #NAMED do
    table.insert(names, NAMED:sub(i, i))
  end

  local rows = { 'Type Name Content' }
  for _, name in ipairs(names) do
    local ok, contents = pcall(vim.fn.getreg, name)
    if ok and type(contents) == 'string' and contents ~= '' then
      local shown = M.holds_secret(contents, values) and placeholder or contents:gsub('\n', '^J')
      table.insert(rows, ('  %s  "%s   %s'):format(register_type(name), name, shown))
    end
  end
  return rows
end

---@return nil
function M.show()
  vim.api.nvim_echo({ { table.concat(M.lines(), '\n') } }, false, {})
end

return M
