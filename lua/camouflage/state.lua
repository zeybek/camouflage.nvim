---@mod camouflage.state State management

local M = {}

M.namespace = vim.api.nvim_create_namespace('camouflage')
M.augroup = vim.api.nvim_create_augroup('camouflage', { clear = true })

---@class BufferState
---@field enabled boolean
---@field variables table[]
---@field parser string|nil

---@type table<number, BufferState>
M.buffers = {}

---@param bufnr number
---@return BufferState
function M.init_buffer(bufnr)
  if not M.buffers[bufnr] then
    M.buffers[bufnr] = { enabled = true, variables = {}, parser = nil }
  end
  return M.buffers[bufnr]
end

---@param bufnr number|nil
---@return BufferState|nil
function M.get_buffer(bufnr)
  return M.buffers[bufnr or vim.api.nvim_get_current_buf()]
end

---@param bufnr number
---@param buf_state BufferState
function M.set_buffer(bufnr, buf_state)
  M.buffers[bufnr] = buf_state
end

---@param bufnr number
---@param updates table
function M.update_buffer(bufnr, updates)
  M.buffers[bufnr] = vim.tbl_extend('force', M.init_buffer(bufnr), updates)
end

---@param bufnr number
function M.remove_buffer(bufnr)
  M.buffers[bufnr] = nil
end

---@param bufnr number|nil
---@return boolean
function M.is_buffer_masked(bufnr)
  local buf_state = M.buffers[bufnr or vim.api.nvim_get_current_buf()]
  return buf_state ~= nil and buf_state.enabled
end

---@param bufnr number
---@param variables table[]
function M.set_variables(bufnr, variables)
  M.init_buffer(bufnr).variables = variables
end

---@param bufnr number
---@return table[]
function M.get_variables(bufnr)
  local buf_state = M.get_buffer(bufnr)
  return buf_state and buf_state.variables or {}
end

function M.clear()
  M.buffers = {}
end

return M
