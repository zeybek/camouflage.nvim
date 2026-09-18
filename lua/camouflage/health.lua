---@mod camouflage.health Health check

-- `:checkhealth camouflage`. When a file isn't masked the reason is usually one
-- of a handful of things, and all of them look the same from the outside: the
-- name matches no pattern, a grammar is missing so a parser fell back, a
-- project file turned masking off, or the project file is waiting to be
-- trusted. This report answers that without reading the source.
--
-- No value is ever printed, the same rule the rest of the plugin follows.

local M = {}

-- vim.health.report_* was renamed in 0.10.
local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local info = health.info or health.report_info

-- Languages a parser asks TreeSitter for, with the parser that falls back.
local TREESITTER_LANGS = {
  { lang = 'json', parser = 'json' },
  { lang = 'yaml', parser = 'yaml' },
  { lang = 'toml', parser = 'toml' },
  { lang = 'xml', parser = 'xml' },
  { lang = 'hcl', parser = 'hcl' },
  { lang = 'dockerfile', parser = 'dockerfile' },
}

---@return string
local function version_string()
  local v = vim.version()
  if type(v) == 'table' then
    return string.format('%d.%d.%d', v.major or 0, v.minor or 0, v.patch or 0)
  end
  return tostring(v)
end

---@param list string[]
---@return string
local function join(list)
  return #list > 0 and table.concat(list, ', ') or 'none'
end

local function check_setup()
  start('camouflage.nvim')
  info('Neovim ' .. version_string())

  if not require('camouflage').is_initialized() then
    warn('setup() has not run, so nothing is masked yet', {
      'Call require("camouflage").setup({}) , or give your plugin manager an `opts` table',
    })
    return false
  end

  local cfg = require('camouflage.config').get()
  if cfg.enabled then
    ok('masking is on')
  else
    warn('masking is off (`enabled = false`, or :CamouflageToggle turned it off)')
  end
  return true
end

local function check_parsers()
  start('Parsers')
  local parsers = require('camouflage.parsers')
  local entries = parsers.list()
  if #entries == 0 then
    warn('no parsers are registered')
    return
  end

  local builtin, user = {}, {}
  for _, entry in ipairs(entries) do
    local bucket = entry.source == 'user' and user or builtin
    table.insert(bucket, entry.name)
  end
  ok(('%d parsers: %s'):format(#entries, join(builtin)))
  if #user > 0 then
    ok('registered at runtime: ' .. join(user))
  end
end

---The buffer the user was looking at. `:checkhealth` runs with its own report
---buffer current, which is never the interesting one.
---@return number
local function inspected_buffer()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype ~= 'checkhealth' and vim.bo[buf].buftype == '' then
      return buf
    end
  end
  local alternate = vim.fn.bufnr('#')
  if alternate ~= -1 and vim.api.nvim_buf_is_valid(alternate) then
    return alternate
  end
  return vim.api.nvim_get_current_buf()
end

local function check_current_buffer()
  start('Current buffer')
  local bufnr = inspected_buffer()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    info('the current buffer has no name, so no parser can match it')
    return
  end

  local parsers = require('camouflage.parsers')
  local _, parser_name = parsers.find_parser_for_file(name)
  local short = vim.fn.fnamemodify(name, ':t')
  if not parser_name then
    info(('no parser handles %s'):format(short), {
      'Add a pattern under `patterns`, or register a parser with require("camouflage").register_parser',
    })
    return
  end

  ok(('%s is handled by the %s parser'):format(short, parser_name))

  local config = require('camouflage.config')
  if not config.is_enabled_for_buffer(bufnr) then
    warn('masking is off for this buffer (`vim.b.camouflage_enabled` or :CamouflageToggle)')
    return
  end

  local state = require('camouflage.state')
  local variables = state.get_variables(bufnr)
  if #variables == 0 then
    info('no values are masked in it right now')
  else
    ok(('%d values are masked in it'):format(#variables))
  end
end

local function check_treesitter()
  start('TreeSitter')
  local ts = require('camouflage.treesitter')
  local missing = {}
  local present = {}
  for _, entry in ipairs(TREESITTER_LANGS) do
    if ts.has_parser(entry.lang) then
      table.insert(present, entry.lang)
    else
      table.insert(missing, entry.lang)
    end
  end

  if #present > 0 then
    ok('grammars installed: ' .. join(present))
  end
  if #missing > 0 then
    info('no grammar for: ' .. join(missing), {
      'Those files use the Lua parser instead, which handles less nesting',
      'Install the grammars with :TSInstall ' .. table.concat(missing, ' '),
    })
  end
end

local function check_project_config()
  start('Project config')
  local config = require('camouflage.config')
  local cfg = config.get()
  local loader = cfg.project_config or {}
  if loader.enabled == false then
    info('project config loading is off')
    return
  end

  local status = require('camouflage.project_config').status()
  if not status.path then
    info(('no %s was found above the current file'):format(loader.filename or '.camouflage.yaml'))
  elseif status.loaded then
    ok('loaded ' .. status.path)
  else
    warn(('%s was found but not applied'):format(status.path), {
      loader.secure and 'It is gated behind vim.secure: run :trust on it' or nil,
    })
  end

  for _, err in ipairs(status.errors or {}) do
    warn('project config: ' .. tostring(err))
  end

  if loader.secure then
    info('project files are gated behind vim.secure (`project_config.secure = true`)')
  end
end

local function check_checks()
  start('Checks')
  local config = require('camouflage.config')
  local cfg = config.get()
  local checks = cfg.checks or {}

  local on = {}
  if (checks.weak_secret or {}).enabled ~= false then
    table.insert(on, 'weak_secret')
  end
  if (checks.expiry or {}).enabled ~= false then
    table.insert(on, 'expiry')
  end
  for _, entry in ipairs(require('camouflage.checks.registry').list()) do
    if entry.name ~= 'weak_secret' and entry.name ~= 'expiry' and entry.name ~= 'pwned' then
      table.insert(on, entry.name)
    end
  end
  ok('offline checks: ' .. join(on))

  local pwned = cfg.pwned or {}
  if not pwned.enabled then
    info('Have I Been Pwned checks are off')
    return
  end

  local auto = {}
  for _, key in ipairs({ 'auto_check', 'check_on_save', 'check_on_change' }) do
    if pwned[key] then
      table.insert(auto, key)
    end
  end
  if #auto > 0 then
    info('HIBP runs by itself for: ' .. join(auto))
  else
    info('HIBP runs only from the :CamouflagePwnedCheck commands')
  end

  if require('camouflage.pwned').is_available() then
    ok('HIBP can reach the network (curl and vim.system are available)')
  else
    warn('HIBP cannot run here', { 'It needs Neovim 0.10+ with vim.system, and curl on PATH' })
  end
end

local function check_integrations()
  start('Integrations')
  local cfg = require('camouflage.config').get()
  local integrations = cfg.integrations or {}

  local plugins = {
    { name = 'telescope', module = 'telescope', option = integrations.telescope ~= false },
    { name = 'snacks', module = 'snacks', option = true },
    {
      name = 'nvim-cmp',
      module = 'cmp',
      option = (integrations.cmp or {}).disable_in_masked ~= false,
    },
  }
  for _, plugin in ipairs(plugins) do
    local installed = pcall(require, plugin.module)
    if installed and plugin.option then
      ok(plugin.name .. ': hooked up')
    elseif installed then
      info(plugin.name .. ': installed, but turned off in `integrations`')
    else
      info(plugin.name .. ': not installed')
    end
  end

  local surfaces = {}
  if integrations.picker_results ~= false then
    table.insert(surfaces, 'picker rows')
  end
  if integrations.quickfix ~= false then
    table.insert(surfaces, 'quickfix')
  end
  if integrations.diff ~= false then
    table.insert(surfaces, 'diffs')
  end
  ok('masked beyond the file itself: ' .. join(surfaces))
end

---Entry point for `:checkhealth camouflage`.
---@return nil
function M.check()
  if not check_setup() then
    return
  end
  check_parsers()
  check_current_buffer()
  check_treesitter()
  check_project_config()
  check_checks()
  check_integrations()
end

return M
