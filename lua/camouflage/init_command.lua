---@mod camouflage.init_command Project config initialization

local M = {}

local log = require('camouflage.log')

---Directory this file was loaded from.
---@return string|nil
local function module_dir()
  local source = debug.getinfo(1, 'S').source
  if source:sub(1, 1) ~= '@' then
    return nil
  end
  return vim.fn.fnamemodify(source:sub(2), ':p:h')
end

--- Get the plugin installation path
---@return string|nil
local function get_plugin_path()
  local dir = module_dir()
  -- Go up from lua/camouflage to the plugin root (git layout)
  return dir and vim.fn.fnamemodify(dir, ':h:h') or nil
end

local module_dir_at_load = module_dir()

local TEMPLATE = 'templates/project_config.yaml'

---Where the template can be, most reliable first. It sits next to this file in
---every layout: lua/camouflage/templates in a git checkout, and
---share/lua/5.1/camouflage/templates in a LuaRocks install (rocks.nvim), where
---neither the runtimepath nor the plugin root lead to it.
---@return string[]
local function template_candidates()
  local candidates = {}
  local dir = module_dir_at_load or module_dir()
  if dir then
    table.insert(candidates, dir .. '/' .. TEMPLATE)
  end
  for _, path in ipairs(vim.api.nvim_get_runtime_file('lua/camouflage/' .. TEMPLATE, false)) do
    table.insert(candidates, path)
  end
  return candidates
end

--- Read the template file
---@return string|nil content, string|nil error
local function read_template()
  for _, path in ipairs(template_candidates()) do
    if vim.fn.filereadable(path) == 1 then
      log.debug('Reading template from: %s', path)
      local ok, lines = pcall(vim.fn.readfile, path)
      if ok and type(lines) == 'table' then
        return table.concat(lines, '\n'), nil
      end
    end
  end
  return nil, 'Could not read template file'
end

--- Find project root (.git parent or cwd)
---@return string
local function get_project_root()
  local git_dir = vim.fn.finddir('.git', '.;')
  if git_dir ~= '' then
    return vim.fn.fnamemodify(git_dir, ':h:p')
  end
  return vim.fn.getcwd()
end

--- Initialize project config file
---@param opts? { force?: boolean, open?: boolean }
---@return boolean|nil success
function M.init(opts)
  opts = opts or {}

  local config = require('camouflage.config').get()
  local filename = (config.project_config and config.project_config.filename) or '.camouflage.yaml'

  local root = get_project_root()
  local target = root .. '/' .. filename

  log.debug('Initializing project config at: %s', target)

  -- Check if file exists
  if vim.fn.filereadable(target) == 1 and not opts.force then
    vim.ui.select({ 'Overwrite', 'Open existing', 'Cancel' }, {
      prompt = filename .. ' already exists:',
    }, function(choice)
      if choice == 'Overwrite' then
        M.init({ force = true, open = opts.open })
      elseif choice == 'Open existing' then
        vim.cmd('edit ' .. vim.fn.fnameescape(target))
      end
      -- Cancel does nothing
    end)
    return
  end

  -- Read template
  local content, err = read_template()
  if not content then
    vim.notify('[camouflage] ' .. (err or 'Unknown error'), vim.log.levels.ERROR)
    return false
  end

  -- Write file
  local write_ok = vim.fn.writefile(vim.split(content, '\n'), target)
  if write_ok ~= 0 then
    vim.notify('[camouflage] Failed to write ' .. target, vim.log.levels.ERROR)
    return false
  end

  vim.notify('[camouflage] Created ' .. target, vim.log.levels.INFO)

  -- Open file
  if opts.open ~= false then
    vim.cmd('edit ' .. vim.fn.fnameescape(target))
  end

  return true
end

-- Expose internal functions for testing
M._get_plugin_path = get_plugin_path
M._read_template = read_template
M._template_candidates = template_candidates
M._get_project_root = get_project_root

return M
