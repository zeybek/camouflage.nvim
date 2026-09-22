---@mod camouflage.integrations.later Install picker hooks once the picker is there

-- Picker integrations wrap a function of the picker plugin, so they can only
-- be installed once that plugin can be required. Doing it from setup() missed
-- every picker loaded after camouflage (packadd, opt packages, mini.deps
-- later()), and with lazy.nvim the `require` pulled the picker in at startup.
--
-- An integration here is installed as soon as its module is already loaded or
-- sits on the runtimepath, and tried again whenever a plugin shows up: lazy.nvim
-- fires `User LazyLoad`, :packadd sources the plugin's files (`SourcePost`),
-- and opening a picker sets its filetype. Nothing is required before its
-- plugin is on the runtimepath, so no picker is loaded early.

local M = {}

---@class CamouflageLaterHook
---@field module string Module the hook wraps, e.g. 'telescope.make_entry'
---@field install fun(): boolean Wraps it, true once it is done

---@type table<string, CamouflageLaterHook>
local pending = {}

---@type number|nil
local group

local scheduled = false

---Whether `module` can be required without loading a plugin that isn't there.
---@param module string
---@return boolean
function M.available(module)
  if package.loaded[module] ~= nil then
    return true
  end
  local path = 'lua/' .. module:gsub('%.', '/')
  return #vim.api.nvim_get_runtime_file(path .. '.lua', false) > 0
    or #vim.api.nvim_get_runtime_file(path .. '/init.lua', false) > 0
end

---Install every pending hook whose module can be required now.
---@return nil
function M.try_all()
  for name, hook in pairs(pending) do
    if M.available(hook.module) then
      local ok, done = pcall(hook.install)
      if ok and done then
        pending[name] = nil
      end
    end
  end
end

---@return nil
local function try_soon()
  if scheduled then
    return
  end
  scheduled = true
  -- After the event: the plugin being sourced or loaded is complete by then.
  vim.schedule(function()
    scheduled = false
    M.try_all()
  end)
end

---@return nil
local function listen()
  if group then
    return
  end
  group = vim.api.nvim_create_augroup('camouflage_later', { clear = true })
  vim.api.nvim_create_autocmd('User', { group = group, pattern = 'LazyLoad', callback = try_soon })
  vim.api.nvim_create_autocmd('SourcePost', { group = group, callback = try_soon })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'snacks_picker_*', 'TelescopePrompt', 'fzf', 'minipick' },
    callback = try_soon,
  })
end

---Install `hook` now if its module is there, or as soon as it shows up.
---@param name string
---@param hook CamouflageLaterHook
---@return nil
function M.add(name, hook)
  pending[name] = hook
  M.try_all()
  if pending[name] then
    listen()
  end
end

---Stop waiting for a hook, for an integration that was turned off.
---@param name string
---@return nil
function M.remove(name)
  pending[name] = nil
end

---Names of the hooks still waiting for their plugin.
---@return string[]
function M.waiting()
  local names = vim.tbl_keys(pending)
  table.sort(names)
  return names
end

---Internal: forget pending hooks and stop listening (used by tests).
---@return nil
function M._reset()
  pending = {}
  scheduled = false
  if group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
    group = nil
  end
end

return M
