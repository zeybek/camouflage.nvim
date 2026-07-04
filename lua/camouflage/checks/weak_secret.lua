---@mod camouflage.checks.weak_secret Offline weak secret quality check
---@brief [[
--- Classifies parsed values with conservative, local heuristics and emits
--- badges through camouflage.checks. No network or provider validation is used.
---@brief ]]

local M = {}

local checks = require('camouflage.checks')
local config_mod = require('camouflage.config')
local hooks = require('camouflage.hooks')
local log = require('camouflage.log')

local CHECK_NAME = 'weak_secret'

---@type integer|nil
local listener_id_before = nil
---@type integer|nil
local listener_id_variable = nil

---@type table<string, boolean>
local warned_patterns = {}

---@type table<table, table<string, boolean>>
local common_value_cache = setmetatable({}, { __mode = 'k' })

local DEFAULT_COMMON_VALUES = {
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
}

local PLACEHOLDER_VALUES = {
  'changeme',
  'change_me',
  'change-me',
  'changeit',
  'replace_me',
  'replace-me',
  'replacewithrealvalue',
  'your_secret_here',
  'your_token_here',
  'your_api_key',
  'example',
  'example_secret',
  'example_token',
  'dummy',
  'placeholder',
  'todo',
  'tbd',
}

local SEQUENCE_VALUES = {
  '1234',
  '12345',
  '123456',
  '1234567',
  '12345678',
  '123456789',
  '1234567890',
  '0123456789',
  'abcdef',
  'qwerty',
  'qwertyuiop',
  'asdfgh',
  'zxcvbn',
}

---@return CamouflageWeakSecretConfig
local function get_config()
  return config_mod.get_check('weak_secret')
end

---@param value string
---@return string
local function trim(value)
  return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

---@param value any
---@return boolean
local function is_blank(value)
  return type(value) ~= 'string' or trim(value) == ''
end

---@param value string
---@return string
local function normalize_value(value)
  local normalized = trim(value):lower()
  if
    (normalized:sub(1, 1) == '"' and normalized:sub(-1) == '"')
    or (normalized:sub(1, 1) == "'" and normalized:sub(-1) == "'")
  then
    normalized = normalized:sub(2, -2)
  end
  return normalized
end

---@param pattern string
---@param kind string
---@param err string
local function warn_invalid_pattern(pattern, kind, err)
  local key = kind .. '\0' .. pattern
  if warned_patterns[key] then
    return
  end
  warned_patterns[key] = true
  local message =
    string.format('[camouflage] invalid weak_secret %s pattern skipped: %s', kind, err)
  if vim.notify_once then
    vim.notify_once(message, vim.log.levels.WARN)
  else
    vim.notify(message, vim.log.levels.WARN)
  end
end

---@param text string
---@param pattern string
---@param kind string
---@return boolean
local function safe_match(text, pattern, kind)
  if type(pattern) ~= 'string' or pattern == '' then
    return false
  end
  local ok, result = pcall(string.find, text, pattern)
  if not ok then
    warn_invalid_pattern(pattern, kind, result)
    return false
  end
  return result ~= nil
end

---@param text string
---@param patterns string[]|nil
---@param kind string
---@return boolean
local function any_pattern_matches(text, patterns, kind)
  if type(patterns) ~= 'table' then
    return false
  end

  local lower_text = text:lower()
  for _, pattern in ipairs(patterns) do
    if safe_match(text, pattern, kind) or safe_match(lower_text, pattern, kind) then
      return true
    end
  end
  return false
end

---@param values string[]|nil
---@return table<string, boolean>
local function to_lookup(values)
  if type(values) == 'table' and common_value_cache[values] then
    return common_value_cache[values]
  end

  local lookup = {}
  if type(values) == 'table' then
    for _, value in ipairs(values) do
      if type(value) == 'string' then
        lookup[normalize_value(value)] = true
      end
    end
  end

  if type(values) == 'table' then
    common_value_cache[values] = lookup
  end
  return lookup
end

---@param value string
---@return boolean
local function is_numeric_or_boolean(value)
  local normalized = normalize_value(value)
  if
    normalized == 'true'
    or normalized == 'false'
    or normalized == 'null'
    or normalized == 'nil'
  then
    return true
  end
  return normalized:match('^[+-]?%d+%.?%d*$') ~= nil
end

---@param value string
---@return boolean
local function is_repeated(value)
  local normalized = normalize_value(value)
  if #normalized < 4 then
    return false
  end
  local first = normalized:sub(1, 1)
  return normalized == first:rep(#normalized)
end

---@param value string
---@return boolean
local function is_simple_sequence(value)
  local normalized = normalize_value(value):gsub('[%s_%-.]', '')
  if #normalized < 4 then
    return false
  end
  for _, seq in ipairs(SEQUENCE_VALUES) do
    if normalized == seq then
      return true
    end
  end
  return false
end

---@param value string
---@param min_length integer
---@return boolean
local function looks_token_like(value, min_length)
  local trimmed = trim(value)
  if trimmed:find('%s') then
    return false
  end
  if trimmed:match('^https?://') or trimmed:match('^postgres://') or trimmed:match('^mysql://') then
    return false
  end
  return trimmed:match('[%w]') ~= nil and #trimmed >= min_length
end

---@param value string
---@return number
local function shannon_entropy(value)
  if value == '' then
    return 0
  end

  local counts = {}
  for i = 1, #value do
    local ch = value:sub(i, i)
    counts[ch] = (counts[ch] or 0) + 1
  end

  local entropy = 0
  for _, count in pairs(counts) do
    local p = count / #value
    entropy = entropy - p * (math.log(p) / math.log(2))
  end
  return entropy
end

---@param value string
---@param cfg CamouflageWeakSecretConfig
---@return boolean
local function is_common_value(value, cfg)
  local lookup = to_lookup(cfg.common_values or DEFAULT_COMMON_VALUES)
  return lookup[normalize_value(value)] == true
end

---@param value string
---@return boolean
local function is_placeholder(value)
  local normalized = normalize_value(value):gsub('[%s_%-.]', '_')
  for _, placeholder in ipairs(PLACEHOLDER_VALUES) do
    if normalized == placeholder or normalized:find(placeholder, 1, true) then
      return true
    end
  end
  return false
end

---@param key string
---@param cfg CamouflageWeakSecretConfig
---@return boolean
local function is_sensitive_key(key, cfg)
  return any_pattern_matches(key, cfg.sensitive_key_patterns, 'sensitive_key')
end

---@param var ParsedVariable
---@param cfg CamouflageWeakSecretConfig
---@return boolean
local function is_ignored(var, cfg)
  return any_pattern_matches(var.key or '', cfg.ignored_key_patterns, 'ignored_key')
    or any_pattern_matches(var.value or '', cfg.ignored_value_patterns, 'ignored_value')
end

---@param reason string
---@param cfg CamouflageWeakSecretConfig
---@return string
local function format_text(reason, cfg)
  local fmt = cfg.virtual_text_format or '[weak: %s]'
  local ok, text = pcall(string.format, fmt, reason)
  if ok and type(text) == 'string' then
    return text
  end
  return '[weak: ' .. reason .. ']'
end

---@param var ParsedVariable
---@param cfg CamouflageWeakSecretConfig|nil
---@return table|nil
function M.classify(var, cfg)
  cfg = cfg or get_config()
  if cfg.enabled == false or not var or type(var.key) ~= 'string' or is_blank(var.value) then
    return nil
  end
  if is_ignored(var, cfg) then
    return nil
  end

  local value = var.value
  local sensitive = is_sensitive_key(var.key, cfg)
  local min_length = cfg.min_length or 8
  local min_sensitive_length = cfg.min_sensitive_length or min_length

  if not sensitive and is_numeric_or_boolean(value) then
    return nil
  end

  local reason
  local score
  if sensitive and is_common_value(value, cfg) then
    reason = 'default'
  elseif sensitive and is_placeholder(value) then
    reason = 'placeholder'
  elseif sensitive and is_repeated(value) then
    reason = 'repeated'
  elseif sensitive and is_simple_sequence(value) then
    reason = 'sequence'
  elseif sensitive and #value < min_sensitive_length then
    reason = 'short'
  elseif sensitive and looks_token_like(value, min_length) then
    score = shannon_entropy(value)
    if score < (cfg.entropy_threshold or 3.0) then
      reason = 'entropy'
    end
  end

  if not reason then
    return nil
  end

  return {
    reason = reason,
    severity = 'warning',
    score = score,
    sensitive_key = sensitive,
    value_length = #value,
  }
end

---@param classification table
---@param var ParsedVariable
---@param cfg CamouflageWeakSecretConfig
---@return CheckResult
local function build_result(classification, var, cfg)
  return {
    severity = classification.severity or 'warning',
    text = cfg.show_virtual_text == false and '' or format_text(classification.reason, cfg),
    hl_group = cfg.virtual_text_hl or 'DiagnosticWarn',
    sign_text = cfg.show_sign and (cfg.sign_text or '!') or nil,
    sign_hl = cfg.sign_hl or cfg.virtual_text_hl or 'DiagnosticWarn',
    line_hl = cfg.line_hl,
    priority = 40,
    data = {
      reason = classification.reason,
      key = var.key,
      value_length = classification.value_length,
      score = classification.score,
      sensitive_key = classification.sensitive_key,
    },
  }
end

---Inspect a single parsed variable and write/clear a weak-secret result.
---@param bufnr integer
---@param var ParsedVariable
function M.inspect_variable(bufnr, var)
  local cfg = get_config()
  local classification = M.classify(var, cfg)
  if not classification then
    return
  end
  checks.set_result(bufnr, var.line_number, CHECK_NAME, build_result(classification, var, cfg))
end

---Run the weak-secret check over the latest parsed variables held in state.
---@param bufnr integer
function M.check_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local state = require('camouflage.state')
  checks.clear_check(bufnr, CHECK_NAME)
  if not M.is_enabled() then
    return
  end

  for _, var in ipairs(state.get_variables(bufnr) or {}) do
    M.inspect_variable(bufnr, var)
  end
end

---Clear weak-secret results from every loaded buffer.
function M.clear_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    checks.clear_check(bufnr, CHECK_NAME)
  end
end

---@return boolean
function M.is_enabled()
  local cfg = get_config()
  return cfg.enabled ~= false
end

---Register hook listeners for the regular decoration pipeline.
function M.setup()
  if not M.is_enabled() then
    M.teardown()
    return
  end

  if listener_id_before then
    pcall(hooks.off, 'before_decorate', listener_id_before)
  end
  listener_id_before = hooks.on('before_decorate', function(bufnr, _filename)
    if M.is_enabled() then
      checks.clear_check(bufnr, CHECK_NAME)
    end
  end)

  if listener_id_variable then
    pcall(hooks.off, 'variable_detected', listener_id_variable)
  end
  listener_id_variable = hooks.on('variable_detected', function(bufnr, var)
    if not M.is_enabled() then
      return
    end
    local ok, err = pcall(M.inspect_variable, bufnr, var)
    if not ok then
      log.debug('weak_secret inspect_variable error: %s', err)
    end
  end)
end

---Remove hook listeners.
function M.teardown()
  if listener_id_before then
    pcall(hooks.off, 'before_decorate', listener_id_before)
    listener_id_before = nil
  end
  if listener_id_variable then
    pcall(hooks.off, 'variable_detected', listener_id_variable)
    listener_id_variable = nil
  end
end

M._entropy = shannon_entropy
M._check_name = CHECK_NAME
M._reset_warnings = function()
  warned_patterns = {}
end

return M
