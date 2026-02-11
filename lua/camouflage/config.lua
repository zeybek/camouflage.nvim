---@mod camouflage.config Configuration

local M = {}

---@class CamouflageEnvParserConfig
---@field include_commented? boolean
---@field include_export? boolean

---@class CamouflageJsonParserConfig
---@field max_depth? number

---@class CamouflageYamlParserConfig
---@field max_depth? number

---@class CamouflageXmlParserConfig
---@field max_depth? number Maximum nesting depth for XML elements

---@class CamouflageParsersConfig
---@field include_commented? boolean
---@field env? CamouflageEnvParserConfig
---@field json? CamouflageJsonParserConfig
---@field yaml? CamouflageYamlParserConfig
---@field xml? CamouflageXmlParserConfig

---@class CamouflageCmpConfig
---@field disable_in_masked? boolean

---@class CamouflageIntegrationsConfig
---@field telescope? boolean
---@field cmp? CamouflageCmpConfig

---@class CamouflageColorsConfig
---@field foreground string|nil Foreground color (hex or color name, nil to use highlight_group)
---@field background string|nil Background color (hex, color name, 'transparent', or nil)
---@field bold boolean|nil Bold text
---@field italic boolean|nil Italic text

---@class CamouflagePatternConfig
---@field file_pattern string|string[]
---@field parser string

---@class CamouflageCustomPatternConfig
---@field file_pattern string|string[]  File pattern (glob)
---@field pattern string                 Lua pattern
---@field key_capture? number            Key capture group (optional)
---@field value_capture number           Value capture group (required)

---@class CamouflageHooksConfig
---@field on_before_decorate? fun(bufnr: number, filename: string): boolean|nil
---@field on_variable_detected? fun(bufnr: number, var: ParsedVariable): boolean|nil
---@field on_after_decorate? fun(bufnr: number, variables: ParsedVariable[]): nil

---@class CamouflageYankConfig
---@field default_register? string Default register ('+' for system clipboard)
---@field notify? boolean Show notification after copy
---@field auto_clear_seconds? number|nil Seconds before auto-clearing clipboard (nil = disabled)
---@field confirm? boolean Require confirmation before copying
---@field confirm_message? string Confirmation message format

---@class CamouflageRevealConfig
---@field highlight_group? string Highlight group for revealed values
---@field notify? boolean Show notification on reveal/hide
---@field follow_cursor? boolean Auto-reveal current line as cursor moves (default: false)

---@class CamouflagePwnedConfig
---@field enabled? boolean Feature toggle (default: true)
---@field auto_check? boolean Check on BufEnter (default: true)
---@field check_on_save? boolean Check on BufWritePost (default: true)
---@field check_on_change? boolean Check on TextChanged with debounce (default: true)
---@field show_sign? boolean Show sign column indicator (default: true)
---@field show_virtual_text? boolean Show virtual text (default: true)
---@field show_line_highlight? boolean Highlight the line (default: true)
---@field sign_text? string Sign icon (default: "⚠")
---@field sign_hl? string Sign highlight group (default: "DiagnosticWarn")
---@field virtual_text_format? string Virtual text format (default: "PWNED (%s)")
---@field virtual_text_hl? string Virtual text highlight (default: "DiagnosticWarn")
---@field line_hl? string Line highlight group (default: "CamouflagePwned")

---@class CamouflageConfig
---@field enabled? boolean
---@field debug? boolean Enable debug logging (default: false)
---@field auto_enable? boolean
---@field style? string
---@field mask_char? string
---@field mask_length? number|nil
---@field max_lines? number|nil
---@field hidden_text? string
---@field highlight_group? string
---@field colors? CamouflageColorsConfig|nil
---@field patterns? CamouflagePatternConfig[]
---@field parsers? CamouflageParsersConfig
---@field integrations? CamouflageIntegrationsConfig
---@field hooks? CamouflageHooksConfig|nil
---@field yank? CamouflageYankConfig|nil Yank configuration
---@field reveal? CamouflageRevealConfig|nil Reveal configuration
---@field pwned? CamouflagePwnedConfig Pwned passwords check configuration
---@field custom_patterns? CamouflageCustomPatternConfig[] Custom patterns for unsupported file types

---@type CamouflageConfig
M.defaults = {
  enabled = true,
  debug = false,
  auto_enable = true,
  style = 'stars',
  mask_char = '*',
  mask_length = nil,
  max_lines = 5000,
  hidden_text = '************************',
  highlight_group = 'Comment',
  colors = nil, -- Custom colors override highlight_group: { foreground = '#808080', background = 'transparent', bold = false, italic = false }
  patterns = {
    { file_pattern = { '.env*', '*.env', '.envrc' }, parser = 'env' },
    { file_pattern = { '*.sh' }, parser = 'env' },
    { file_pattern = { '*.json' }, parser = 'json' },
    { file_pattern = { '*.yaml', '*.yml' }, parser = 'yaml' },
    { file_pattern = { '*.toml' }, parser = 'toml' },
    { file_pattern = { '*.properties', '*.ini', '*.conf', 'credentials' }, parser = 'properties' },
    { file_pattern = { '.netrc', '_netrc' }, parser = 'netrc' },
    { file_pattern = { '*.xml' }, parser = 'xml' },
    { file_pattern = { '*.http' }, parser = 'http' },
  },
  parsers = {
    include_commented = true,
    env = { include_commented = true, include_export = true },
    json = { max_depth = 10 },
    yaml = { max_depth = 10 },
  },
  integrations = {
    telescope = true,
    cmp = { disable_in_masked = true },
  },
  hooks = nil,
  yank = {
    default_register = '+',
    notify = true,
    auto_clear_seconds = 30,
    confirm = true,
    confirm_message = 'Copy value of "%s" to clipboard?',
  },
  reveal = {
    highlight_group = 'CamouflageRevealed',
    notify = false,
    follow_cursor = false,
  },
  pwned = {
    enabled = true,
    auto_check = true,
    check_on_save = true,
    check_on_change = true,
    show_sign = true,
    show_virtual_text = true,
    show_line_highlight = true,
    sign_text = '⚠',
    sign_hl = 'DiagnosticWarn',
    virtual_text_format = 'PWNED (%s)',
    virtual_text_hl = 'DiagnosticWarn',
    line_hl = 'CamouflagePwned',
  },
  custom_patterns = {},
}

---@type CamouflageConfig
M.options = {}

---@param opts CamouflageConfig|nil
---@return CamouflageConfig|nil
local function validate_config(opts)
  if not opts then
    return opts
  end

  if opts.style then
    local styles = require('camouflage.styles')
    if not styles.is_valid_style(opts.style) then
      vim.notify(
        '[camouflage] Invalid style "' .. opts.style .. '", using "stars"',
        vim.log.levels.WARN
      )
      opts.style = nil
    end
  end

  if opts.max_lines and (type(opts.max_lines) ~= 'number' or opts.max_lines < 1) then
    vim.notify('[camouflage] Invalid max_lines, using default', vim.log.levels.WARN)
    opts.max_lines = nil
  end

  return opts
end

---@param opts CamouflageConfig|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', {}, M.defaults, validate_config(opts) or {})
end

---@return CamouflageConfig
function M.get()
  return vim.tbl_isempty(M.options) and M.defaults or M.options
end

---@param key string
---@param value any
function M.set(key, value)
  local keys = vim.split(key, '.', { plain = true })
  local tbl = M.options
  for i = 1, #keys - 1 do
    tbl = tbl[keys[i]]
    if tbl == nil then
      return
    end
  end
  if tbl ~= nil then
    local last_key = keys[#keys]
    local old_value = tbl[last_key]

    -- Only update and refresh if value actually changed
    if old_value ~= value then
      tbl[last_key] = value

      -- Hot reload: refresh all buffers when config changes
      -- Use vim.schedule to avoid issues during startup
      vim.schedule(function()
        local ok, core = pcall(require, 'camouflage.core')
        if ok and core.refresh_all then
          core.refresh_all()
        end
      end)
    end
  end
end

---@return boolean
function M.is_enabled()
  return M.get().enabled
end

---@return string
function M.get_style()
  return M.get().style
end

---Get effective configuration for a specific buffer, merging buffer-local overrides
---Buffer variables supported:
---  vim.b.camouflage_enabled - boolean
---  vim.b.camouflage_style - string
---  vim.b.camouflage_mask_char - string
---  vim.b.camouflage_mask_length - number
---  vim.b.camouflage_highlight_group - string
---@param bufnr number|nil Buffer number (nil for current buffer)
---@return CamouflageConfig
function M.get_for_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local base_config = M.get()

  -- Check if buffer is valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return base_config
  end

  -- Create a copy of the base config
  local buf_config = vim.tbl_deep_extend('force', {}, base_config)

  -- Override with buffer-local variables if they exist
  local ok, buf_enabled = pcall(vim.api.nvim_buf_get_var, bufnr, 'camouflage_enabled')
  if ok and type(buf_enabled) == 'boolean' then
    buf_config.enabled = buf_enabled
  end

  local ok_style, buf_style = pcall(vim.api.nvim_buf_get_var, bufnr, 'camouflage_style')
  if ok_style and type(buf_style) == 'string' then
    local styles = require('camouflage.styles')
    if styles.is_valid_style(buf_style) then
      buf_config.style = buf_style
    end
  end

  local ok_char, buf_mask_char = pcall(vim.api.nvim_buf_get_var, bufnr, 'camouflage_mask_char')
  if ok_char and type(buf_mask_char) == 'string' and #buf_mask_char > 0 then
    buf_config.mask_char = buf_mask_char
  end

  local ok_length, buf_mask_length =
    pcall(vim.api.nvim_buf_get_var, bufnr, 'camouflage_mask_length')
  if ok_length and type(buf_mask_length) == 'number' and buf_mask_length > 0 then
    buf_config.mask_length = buf_mask_length
  end

  local ok_hl, buf_highlight = pcall(vim.api.nvim_buf_get_var, bufnr, 'camouflage_highlight_group')
  if ok_hl and type(buf_highlight) == 'string' and #buf_highlight > 0 then
    buf_config.highlight_group = buf_highlight
  end

  return buf_config
end

---Check if masking is enabled for a specific buffer
---Takes into account both global and buffer-local settings
---@param bufnr number|nil Buffer number (nil for current buffer)
---@return boolean
function M.is_enabled_for_buffer(bufnr)
  return M.get_for_buffer(bufnr).enabled
end

return M
