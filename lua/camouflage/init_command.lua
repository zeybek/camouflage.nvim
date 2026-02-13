---@mod camouflage.init_command Project config initialization

local M = {}

local log = require('camouflage.log')

--- Get the plugin installation path
---@return string|nil
local function get_plugin_path()
  -- Use debug.getinfo to find this file's path
  local source = debug.getinfo(1, 'S').source
  if source:sub(1, 1) == '@' then
    source = source:sub(2)
  end
  -- Go up from lua/camouflage/init_command.lua to plugin root
  return vim.fn.fnamemodify(source, ':h:h:h')
end

--- Read the template file
---@return string|nil content, string|nil error
local function read_template()
  local plugin_path = get_plugin_path()
  if not plugin_path then
    return nil, 'Could not determine plugin path'
  end

  local template_path = plugin_path .. '/lua/camouflage/templates/project_config.yaml'
  log.debug('Reading template from: %s', template_path)

  local ok, lines = pcall(vim.fn.readfile, template_path)
  if not ok or type(lines) ~= 'table' then
    return nil, 'Could not read template file'
  end

  return table.concat(lines, '\n'), nil
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
M._get_project_root = get_project_root

return M
