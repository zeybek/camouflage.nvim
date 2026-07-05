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

---@class CamouflageHclParserConfig
---@field max_depth? number Maximum block nesting depth

---@class CamouflageParsersConfig
---@field include_commented? boolean
---@field env? CamouflageEnvParserConfig
---@field json? CamouflageJsonParserConfig
---@field yaml? CamouflageYamlParserConfig
---@field xml? CamouflageXmlParserConfig
---@field hcl? CamouflageHclParserConfig

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
---@field sign_text? string Sign icon (default: "!")
---@field sign_hl? string Sign highlight group (default: "DiagnosticWarn")
---@field virtual_text_format? string Virtual text format (default: "PWNED (%s)")
---@field virtual_text_prefix? string Deprecated: prefix for virtual text, use virtual_text_format instead
---@field virtual_text_hl? string Virtual text highlight (default: "DiagnosticWarn")
---@field line_hl? string Line highlight group (default: "CamouflagePwned")

---@class CamouflageExpiryRefreshConfig
---@field on_buf_enter? boolean Re-check on BufEnter (default: true)
---@field on_save? boolean Re-check on BufWritePost (default: true)
---@field on_change? boolean Re-check on TextChanged (debounced) (default: true)
---@field auto_interval? integer Background re-render interval in seconds, 0 disables (default: 60)

---@class CamouflageExpiryConfig
---@field enabled? boolean (default: true)
---@field show_threshold_seconds? integer Show badge only when remaining < this (default: 86400 = 24h)
---@field warn_threshold_seconds? integer Switch badge to warning color when remaining < this (default: 3600 = 1h)
---@field show_provider? boolean Append provider name from `iss` claim (default: true)
---@field refresh? CamouflageExpiryRefreshConfig
---@field hl_valid? string Highlight when token is valid but within show_threshold (default: 'Comment')
---@field hl_warning? string Highlight when within warn_threshold (default: 'DiagnosticWarn')
---@field hl_expired? string Highlight when expired (default: 'DiagnosticError')

---@class CamouflageWeakSecretConfig
---@field enabled? boolean Feature toggle (default: true)
---@field min_length? integer General minimum length used by future heuristics (default: 8)
---@field min_sensitive_length? integer Minimum length for sensitive keys (default: 12)
---@field entropy_threshold? number Shannon entropy threshold for token-like values (default: 3.0)
---@field sensitive_key_patterns? string[] Lua patterns that mark a key as secret-like
---@field ignored_key_patterns? string[] Lua patterns for keys to skip
---@field ignored_value_patterns? string[] Lua patterns for values to skip
---@field common_values? string[] Common/default weak values
---@field show_sign? boolean Show sign column indicator
---@field sign_text? string Sign text
---@field sign_hl? string Sign highlight group
---@field show_virtual_text? boolean Show badge virtual text
---@field virtual_text_format? string Badge text format with one `%s` reason placeholder
---@field virtual_text_hl? string Badge highlight group
---@field line_hl? string|nil Whole-line highlight group

---@class CamouflageBadgesConfig
---@field position? string Where badges render: 'right_align' | 'eol' | 'inline' (default: 'right_align')
---@field separator? string Text inserted between adjacent badges (default: ' ')
---@field separator_hl? string Highlight for the separator (default: 'Comment')

---@class CamouflageAuditConfig
---@field ignore_patterns? string[] Root-relative globs or basename globs skipped by workspace audit
---@field max_files_per_chunk? integer Number of discovered files processed per scheduled async chunk
---@field destination? string "quickfix" | "loclist" (default: "quickfix")
---@field open? boolean Open quickfix/location-list after findings are written
---@field notify? boolean Show audit completion notifications

---@class CamouflagePolicyValueLengthConfig
---@field min? number
---@field max? number

---@class CamouflagePolicyRuleConfig
---@field id? string Stable rule identifier for status/debug metadata
---@field action string "mask" | "ignore"
---@field allow_force? boolean Allow this mask rule to override broader ignore rules
---@field path? string|string[] Root-relative glob(s)
---@field basename? string|string[] Basename glob(s)
---@field parser? string|string[] Parser name(s)
---@field key? string|string[] Lua pattern(s) matched against parsed keys
---@field nested? boolean Match nested parser output
---@field commented? boolean Match commented parser output
---@field value_length? CamouflagePolicyValueLengthConfig
---@field value_shape? string|string[] "empty" | "non_empty" | "numeric" | "boolean" | "quoted" | "jwt_like" | "token_like"
---@field value_prefix? string|string[] Literal value prefix shape(s), never logged
---@field value_suffix? string|string[] Literal value suffix shape(s), never logged

---@class CamouflagePolicyConfig
---@field enabled? boolean Enable declarative policy evaluation
---@field default_action? string "mask" | "ignore" for unmatched parsed variables
---@field terminal_path_ignores? string[] Root-relative globs ignored before ordered rules unless allow_force mask matches
---@field rules? CamouflagePolicyRuleConfig[] Ordered policy rules

---@class CamouflageChecksConfig
---@field badges? CamouflageBadgesConfig
---@field pwned? CamouflagePwnedConfig
---@field expiry? CamouflageExpiryConfig
---@field weak_secret? CamouflageWeakSecretConfig

---@class CamouflageProjectConfigLoaderConfig
---@field enabled? boolean Enable repo config loading (default: true)
---@field filename? string Project config filename (default: ".camouflage.yaml")
---@field notify? boolean Show warnings for project config parse/validation issues (default: true)
---@field secure? boolean Gate the project file behind vim.secure.read / :trust (default: false)
---@field watch_enabled? boolean Watch .camouflage.yaml for runtime changes (default: true)
---@field watch_backend? string "auto" | "autocmd" | "fs" | "both" (default: "auto")
---@field watch_debounce_ms? number Debounce for change events (default: 200)
---@field max_watched_roots? number Max roots to watch in one session (default: 10)
---@field notify_on_reload? boolean Show info notification after successful live reload (default: false)

---@class CamouflageConfig
---@field enabled? boolean
---@field debug? boolean Enable debug logging (default: false)
---@field auto_enable? boolean
---@field debounce_ms? number Debounce delay in ms for TextChanged masking (default: 150, 0 = instant)
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
---@field project_config? CamouflageProjectConfigLoaderConfig Repo-level project config loading
---@field audit? CamouflageAuditConfig Workspace audit configuration
---@field policy? CamouflagePolicyConfig Declarative data-only masking policy
---@field checks? CamouflageChecksConfig Per-check configuration (pwned, expiry, ...)

---@type CamouflageConfig
M.defaults = {
  enabled = true,
  debug = false,
  auto_enable = true,
  debounce_ms = 150,
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
    { file_pattern = { '*.tf', '*.tfvars', '*.hcl' }, parser = 'hcl' },
    {
      file_pattern = {
        'Dockerfile',
        'Dockerfile.*',
        '*.dockerfile',
        'Containerfile',
        'Containerfile.*',
      },
      parser = 'dockerfile',
    },
  },
  parsers = {
    include_commented = true,
    env = { include_commented = true, include_export = true },
    json = { max_depth = 10 },
    yaml = { max_depth = 10 },
    xml = { max_depth = 10 },
    hcl = { max_depth = 10 },
    dockerfile = {},
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
    sign_text = '!',
    sign_hl = 'DiagnosticWarn',
    virtual_text_format = 'PWNED (%s)',
    virtual_text_hl = 'DiagnosticWarn',
    line_hl = 'CamouflagePwned',
  },
  custom_patterns = {},
  audit = {
    ignore_patterns = { '.git', '.git/**', 'node_modules', 'node_modules/**' },
    max_files_per_chunk = 50,
    destination = 'quickfix',
    open = true,
    notify = true,
  },
  policy = {
    enabled = true,
    default_action = 'mask',
    terminal_path_ignores = {},
    rules = {},
  },
  checks = {
    badges = {
      position = 'right_align',
      separator = ' ',
      separator_hl = 'Comment',
    },
    expiry = {
      enabled = true,
      show_threshold_seconds = 86400,
      warn_threshold_seconds = 3600,
      show_provider = true,
      refresh = {
        on_buf_enter = true,
        on_save = true,
        on_change = true,
        auto_interval = 60,
      },
      hl_valid = 'Comment',
      hl_warning = 'DiagnosticWarn',
      hl_expired = 'DiagnosticError',
    },
    weak_secret = {
      enabled = true,
      min_length = 8,
      min_sensitive_length = 12,
      entropy_threshold = 3.0,
      sensitive_key_patterns = {
        'password',
        'passwd',
        'passphrase',
        'secret',
        'token',
        'api[_%-]*key',
        'access[_%-]*key',
        'private[_%-]*key',
        'client[_%-]*secret',
        'auth[_%-]*token',
        'credential',
      },
      ignored_key_patterns = {},
      ignored_value_patterns = {},
      common_values = {
        'password',
        'password1',
        'password123',
        'secret',
        'secret123',
        'changeme',
        'changeit',
        'admin',
        'default',
        'test',
        'testing',
        'demo',
        'dummy',
        'qwerty',
        'letmein',
        'welcome',
        'hunter2',
      },
      show_sign = false,
      sign_text = '!',
      sign_hl = 'DiagnosticWarn',
      show_virtual_text = true,
      virtual_text_format = '[weak: %s]',
      virtual_text_hl = 'DiagnosticWarn',
      line_hl = nil,
    },
  },
  project_config = {
    enabled = true,
    filename = '.camouflage.yaml',
    notify = true,
    secure = false,
    watch_enabled = true,
    watch_backend = 'auto',
    watch_debounce_ms = 200,
    max_watched_roots = 10,
    notify_on_reload = false,
  },
}

---@type CamouflageConfig
M.options = {}

---@type CamouflageConfig
M.user_options = {}

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

---Reconcile the legacy top-level `pwned` key with the canonical `checks.pwned`
---namespace. Both names are aliased to ONE shared table (new namespace wins on
---conflict), so cfg.pwned and cfg.checks.pwned can never drift — in particular,
---`checks = { pwned = { enabled = false } }` now actually disables the feature.
---Idempotent.
---@param options table
local function apply_legacy_aliases(options)
  options.checks = options.checks or {}
  local merged = vim.tbl_deep_extend('force', {}, options.pwned or {}, options.checks.pwned or {})
  options.pwned = merged
  options.checks.pwned = merged
end

---Warn once when a cosmetic-only style is in effect, so it is not mistaken for
---protective masking. Fires for style set via setup() opts OR a project file.
---vim.notify_once dedupes by message, so it fires at most once per session.
---@param options table
local function warn_cosmetic_styles(options)
  if options.style == 'scramble' then
    vim.notify_once(
      '[camouflage] style "scramble" is cosmetic, not protective: the mask is a '
        .. "shuffle of the real characters and leaks the value's length and character set.",
      vim.log.levels.WARN
    )
  end
end

---@param opts CamouflageConfig|nil
function M.setup(opts)
  local user_opts = validate_config(opts) or {}
  M.user_options = vim.tbl_deep_extend('force', {}, user_opts)

  -- Merge user project_config with defaults to get effective settings
  local effective_project_config = vim.tbl_deep_extend(
    'force',
    {},
    M.defaults.project_config or {},
    M.user_options.project_config or {}
  )
  local project_config_opts = require('camouflage.project_config').load(effective_project_config)
  M.options = vim.tbl_deep_extend('force', {}, M.defaults, M.user_options, project_config_opts)
  apply_legacy_aliases(M.options)
  warn_cosmetic_styles(M.options)
end

---Reload project config and rebuild effective options.
---Returns false if project config exists but is invalid.
---@return boolean applied
---@return CamouflageProjectConfigStatus status
function M.reload_project_config()
  local project_config = require('camouflage.project_config')
  local project_config_opts = project_config.load(M.user_options.project_config or {})
  local status = project_config.status()

  -- Keep current effective options if the file exists but could not be parsed/validated.
  if status.path ~= nil and not status.loaded and #status.errors > 0 then
    return false, status
  end

  M.options = vim.tbl_deep_extend('force', {}, M.defaults, M.user_options, project_config_opts)
  apply_legacy_aliases(M.options)
  warn_cosmetic_styles(M.options)
  return true, status
end

---@return CamouflageConfig
function M.get()
  return vim.tbl_isempty(M.options) and M.defaults or M.options
end

---Get the effective config table for a named check (e.g. 'pwned'), the
---canonical accessor for the checks.* namespace. Always returns a table.
---@param name string
---@return table
function M.get_check(name)
  local checks = M.get().checks or {}
  return checks[name] or {}
end

---Set a dotted config key. Returns whether the value was applied; warns (rather
---than silently no-op'ing) when an intermediate path segment is missing or is
---not a table.
---@param key string
---@param value any
---@return boolean applied
function M.set(key, value)
  local keys = vim.split(key, '.', { plain = true })
  local tbl = M.options
  for i = 1, #keys - 1 do
    local nxt = tbl[keys[i]]
    if type(nxt) ~= 'table' then
      vim.notify(
        string.format(
          '[camouflage] config.set: invalid key path "%s" ("%s" is %s)',
          key,
          table.concat(vim.list_slice(keys, 1, i), '.'),
          nxt == nil and 'nil' or type(nxt)
        ),
        vim.log.levels.WARN
      )
      return false
    end
    tbl = nxt
  end

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

  return true
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

  -- Fast path: with no buffer-local overrides, return the shared config without
  -- the deep copy below (this runs on every decoration pass).
  local b = vim.b[bufnr]
  if
    b.camouflage_enabled == nil
    and b.camouflage_style == nil
    and b.camouflage_mask_char == nil
    and b.camouflage_mask_length == nil
    and b.camouflage_highlight_group == nil
  then
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
