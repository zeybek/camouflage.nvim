---@mod camouflage.state State management

local M = {}

M.namespace = vim.api.nvim_create_namespace('camouflage')
M.augroup = vim.api.nvim_create_augroup('camouflage', { clear = true })
M.runtime_augroup = vim.api.nvim_create_augroup('camouflage_runtime', { clear = true })

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

---Empty the stored variables for a buffer WITHOUT creating state for it.
---Used when decorations are cleared so yank/reveal/pwned don't act on stale,
---now-unmasked data.
---@param bufnr number
function M.clear_variables(bufnr)
  local buf_state = M.buffers[bufnr]
  if buf_state then
    buf_state.variables = {}
  end
end

---Mark a masked buffer as needing re-decoration the next time it is displayed
---(used by refresh_all for buffers not currently in a window).
---@param bufnr number
function M.mark_dirty(bufnr)
  local buf_state = M.buffers[bufnr]
  if buf_state then
    buf_state.dirty = true
  end
end

---@param bufnr number
function M.clear_dirty(bufnr)
  local buf_state = M.buffers[bufnr]
  if buf_state then
    buf_state.dirty = nil
  end
end

---@param bufnr number
---@return boolean
function M.is_dirty(bufnr)
  local buf_state = M.buffers[bufnr]
  return buf_state ~= nil and buf_state.dirty == true
end

---Clear all buffer state
---@return nil
function M.clear()
  M.buffers = {}
end

return M
