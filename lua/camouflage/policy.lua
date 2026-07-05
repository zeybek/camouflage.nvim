---@mod camouflage.policy Declarative masking policy evaluator
---@brief [[
--- Applies data-only policy rules to parsed variables. The evaluator never
--- mutates parser output and never stores or logs plaintext values in policy
--- decisions, warnings, or stats.
---@brief ]]

local M = {}

local log = require('camouflage.log')

local VALID_ACTIONS = {
  mask = true,
  ignore = true,
}

local VALID_VALUE_SHAPES = {
  empty = true,
  non_empty = true,
  numeric = true,
  boolean = true,
  quoted = true,
  jwt_like = true,
  token_like = true,
}

---@type table<string, boolean>
local warned_messages = {}

---@param msg string
local function warn_once(msg)
  if warned_messages[msg] then
    return
  end
  warned_messages[msg] = true

  if vim.notify_once then
    vim.notify_once(msg, vim.log.levels.WARN)
  else
    vim.notify(msg, vim.log.levels.WARN)
  end
end

function M._reset_warnings()
  warned_messages = {}
end

---@param value any
---@return string
local function normalize_path(value)
  return tostring(value or ''):gsub('\\', '/')
end

---@param path string
---@return string
local function basename(path)
  return vim.fn.fnamemodify(path, ':t')
end

---@param path string
---@param root string|nil
---@return string
local function relative_path(path, root)
  local normalized = normalize_path(path)
  local normalized_root = normalize_path(root or ''):gsub('/+$', '')
  if normalized_root == '' then
    return normalized
  end
  if normalized == normalized_root then
    return basename(normalized)
  end
  if normalized:sub(1, #normalized_root + 1) == normalized_root .. '/' then
    return normalized:sub(#normalized_root + 2)
  end
  return normalized
end

M.relative_path = relative_path

---@param glob string
---@return string
local function glob_to_pattern(glob)
  local token = '\1'
  local escaped = glob:gsub('\\', '/'):gsub('%*%*', token)
  escaped = escaped:gsub('([%^%$%(%)%%%.%[%]%+%-])', '%%%1')
  escaped = escaped:gsub('%*', '[^/]*'):gsub('%?', '[^/]')
  escaped = escaped:gsub(token, '.*')
  return '^' .. escaped .. '$'
end

---@param text string
---@param pattern string
---@return boolean
local function matches_compiled_glob(text, pattern)
  return normalize_path(text):match(pattern) ~= nil
end

---@param value any
---@param field string
---@param rule_id string
---@return string[]|nil
---@return boolean ok
local function string_list(value, field, rule_id)
  if value == nil then
    return nil, true
  end
  if type(value) == 'string' then
    return { value }, true
  end
  if type(value) ~= 'table' then
    warn_once(
      string.format(
        '[camouflage] invalid policy rule "%s": %s must be a string or list',
        rule_id,
        field
      )
    )
    return nil, false
  end

  local result = {}
  for _, item in ipairs(value) do
    if type(item) ~= 'string' or item == '' then
      warn_once(
        string.format(
          '[camouflage] invalid policy rule "%s": %s contains a non-string item',
          rule_id,
          field
        )
      )
      return nil, false
    end
    table.insert(result, item)
  end
  return result, true
end

---@param value any
---@param field string
---@param rule_id string
---@return table[]|nil
---@return boolean ok
local function glob_list(value, field, rule_id)
  local items, ok = string_list(value, field, rule_id)
  if not ok or not items then
    return nil, ok
  end

  local result = {}
  for _, item in ipairs(items) do
    table.insert(result, {
      raw = item,
      pattern = glob_to_pattern(item),
    })
  end
  return result, true
end

---@param value any
---@param field string
---@param rule_id string
---@return string[]|nil
---@return boolean ok
local function lua_pattern_list(value, field, rule_id)
  local items, ok = string_list(value, field, rule_id)
  if not ok or not items then
    return nil, ok
  end

  for _, pattern in ipairs(items) do
    local pattern_ok, err = pcall(string.find, '', pattern)
    if not pattern_ok then
      warn_once(
        string.format(
          '[camouflage] invalid policy rule "%s": %s pattern skipped (%s)',
          rule_id,
          field,
          tostring(err)
        )
      )
      return nil, false
    end
  end

  return items, true
end

---@param value any
---@param field string
---@param rule_id string
---@return boolean|nil
---@return boolean ok
local function boolean_field(value, field, rule_id)
  if value == nil then
    return nil, true
  end
  if type(value) ~= 'boolean' then
    warn_once(
      string.format('[camouflage] invalid policy rule "%s": %s must be boolean', rule_id, field)
    )
    return nil, false
  end
  return value, true
end

---@param value any
---@param rule_id string
---@return table|nil
---@return boolean ok
local function value_length(value, rule_id)
  if value == nil then
    return nil, true
  end
  if type(value) ~= 'table' then
    warn_once(
      string.format('[camouflage] invalid policy rule "%s": value_length must be a table', rule_id)
    )
    return nil, false
  end

  local min = value.min
  local max = value.max
  if min ~= nil and type(min) ~= 'number' then
    warn_once(
      string.format(
        '[camouflage] invalid policy rule "%s": value_length.min must be a number',
        rule_id
      )
    )
    return nil, false
  end
  if max ~= nil and type(max) ~= 'number' then
    warn_once(
      string.format(
        '[camouflage] invalid policy rule "%s": value_length.max must be a number',
        rule_id
      )
    )
    return nil, false
  end
  if min ~= nil and max ~= nil and min > max then
    warn_once(
      string.format('[camouflage] invalid policy rule "%s": value_length min exceeds max', rule_id)
    )
    return nil, false
  end

  return { min = min, max = max }, true
end

---@param value any
---@param rule_id string
---@return string[]|nil
---@return boolean ok
local function value_shapes(value, rule_id)
  local items, ok = string_list(value, 'value_shape', rule_id)
  if not ok or not items then
    return nil, ok
  end

  for _, shape in ipairs(items) do
    if not VALID_VALUE_SHAPES[shape] then
      warn_once(
        string.format(
          '[camouflage] invalid policy rule "%s": unknown value_shape "%s"',
          rule_id,
          shape
        )
      )
      return nil, false
    end
  end
  return items, true
end

---@param pattern string
---@return string|nil
local function exact_key_from_pattern(pattern)
  local body = pattern:match('^%^(.*)%$$')
  if not body or body == '' then
    return nil
  end
  if body:find('[%(%)%.%%%+%-%*%?%[%]%^%$]') then
    return nil
  end
  return body
end

---@param text string
---@param patterns string[]|nil
---@param exact table<string, boolean>|nil
---@return boolean
local function any_lua_pattern_matches(text, patterns, exact)
  if not patterns and not exact then
    return true
  end
  if exact and exact[text] then
    return true
  end
  if not patterns then
    return false
  end
  for _, pattern in ipairs(patterns) do
    if text:find(pattern) then
      return true
    end
  end
  return false
end

---@param text string
---@param globs table[]|nil
---@return boolean
local function any_glob_matches(text, globs)
  if not globs then
    return true
  end
  for _, glob in ipairs(globs) do
    if matches_compiled_glob(text, glob.pattern) then
      return true
    end
  end
  return false
end

---@param value string
---@param prefixes string[]|nil
---@return boolean
local function any_prefix_matches(value, prefixes)
  if not prefixes then
    return true
  end
  for _, prefix in ipairs(prefixes) do
    if value:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

---@param value string
---@param suffixes string[]|nil
---@return boolean
local function any_suffix_matches(value, suffixes)
  if not suffixes then
    return true
  end
  for _, suffix in ipairs(suffixes) do
    if suffix == '' or value:sub(-#suffix) == suffix then
      return true
    end
  end
  return false
end

---@param values string[]|nil
---@param candidate string
---@return boolean
local function any_string_equals(values, candidate)
  if not values then
    return true
  end
  for _, value in ipairs(values) do
    if value == candidate then
      return true
    end
  end
  return false
end

---@param value string
---@return boolean
local function is_numeric(value)
  return value:match('^[+-]?%d+%.?%d*$') ~= nil
end

---@param value string
---@return boolean
local function is_boolean(value)
  local lower = value:lower()
  return lower == 'true' or lower == 'false'
end

---@param value string
---@return boolean
local function is_quoted(value)
  return (value:sub(1, 1) == '"' and value:sub(-1) == '"')
    or (value:sub(1, 1) == "'" and value:sub(-1) == "'")
end

---@param value string
---@return boolean
local function is_jwt_like(value)
  return value:match('^[A-Za-z0-9_-]+%.[A-Za-z0-9_-]+%.[A-Za-z0-9_-]+$') ~= nil
end

---@param value string
---@return boolean
local function is_token_like(value)
  return #value >= 8 and value:find('%s') == nil and value:find('[%w]') ~= nil
end

---@param value string
---@param shape string
---@return boolean
local function value_has_shape(value, shape)
  if shape == 'empty' then
    return value == ''
  end
  if shape == 'non_empty' then
    return value ~= ''
  end
  if shape == 'numeric' then
    return is_numeric(value)
  end
  if shape == 'boolean' then
    return is_boolean(value)
  end
  if shape == 'quoted' then
    return is_quoted(value)
  end
  if shape == 'jwt_like' then
    return is_jwt_like(value)
  end
  if shape == 'token_like' then
    return is_token_like(value)
  end
  return false
end

---@param value string
---@param shapes string[]|nil
---@return boolean
local function any_value_shape_matches(value, shapes)
  if not shapes then
    return true
  end
  for _, shape in ipairs(shapes) do
    if value_has_shape(value, shape) then
      return true
    end
  end
  return false
end

---@param rule table
---@param index integer
---@return table|nil
local function normalize_rule(rule, index)
  local fallback_id = 'rule-' .. index
  if type(rule) ~= 'table' then
    warn_once(
      string.format('[camouflage] invalid policy rule "%s": rule must be a table', fallback_id)
    )
    return nil
  end

  local rule_id = tostring(rule.id or fallback_id)
  if not VALID_ACTIONS[rule.action] then
    warn_once(
      string.format(
        '[camouflage] invalid policy rule "%s": action must be "mask" or "ignore"',
        rule_id
      )
    )
    return nil
  end

  local normalized = {
    id = rule_id,
    action = rule.action,
    allow_force = rule.allow_force == true,
  }

  local ok
  normalized.path, ok = glob_list(rule.path, 'path', rule_id)
  if not ok then
    return nil
  end
  normalized.basename, ok = glob_list(rule.basename, 'basename', rule_id)
  if not ok then
    return nil
  end
  normalized.parser, ok = string_list(rule.parser, 'parser', rule_id)
  if not ok then
    return nil
  end
  normalized.key, ok = lua_pattern_list(rule.key, 'key', rule_id)
  if not ok then
    return nil
  end
  if normalized.key then
    local pattern_keys = {}
    local exact_keys = {}
    for _, pattern in ipairs(normalized.key) do
      local exact = exact_key_from_pattern(pattern)
      if exact then
        exact_keys[exact] = true
      else
        table.insert(pattern_keys, pattern)
      end
    end
    normalized.key = #pattern_keys > 0 and pattern_keys or nil
    normalized.key_exact = next(exact_keys) and exact_keys or nil
  end
  normalized.nested, ok = boolean_field(rule.nested, 'nested', rule_id)
  if not ok then
    return nil
  end
  normalized.commented, ok = boolean_field(rule.commented, 'commented', rule_id)
  if not ok then
    return nil
  end
  normalized.value_length, ok = value_length(rule.value_length, rule_id)
  if not ok then
    return nil
  end
  normalized.value_shape, ok = value_shapes(rule.value_shape, rule_id)
  if not ok then
    return nil
  end
  normalized.value_prefix, ok = string_list(rule.value_prefix, 'value_prefix', rule_id)
  if not ok then
    return nil
  end
  normalized.value_suffix, ok = string_list(rule.value_suffix, 'value_suffix', rule_id)
  if not ok then
    return nil
  end

  return normalized
end

---@param policy_cfg table|nil
---@return table
local function normalize_policy(policy_cfg)
  if policy_cfg == nil then
    policy_cfg = {}
  elseif type(policy_cfg) ~= 'table' then
    warn_once('[camouflage] invalid policy config: policy must be a table')
    policy_cfg = {}
  end

  local enabled = policy_cfg.enabled ~= false
  local default_action = policy_cfg.default_action or 'mask'
  if not VALID_ACTIONS[default_action] then
    warn_once('[camouflage] invalid policy default_action: using "mask"')
    default_action = 'mask'
  end

  local terminal_path_ignores = {}
  local raw_terminal, terminal_ok =
    glob_list(policy_cfg.terminal_path_ignores, 'terminal_path_ignores', 'policy')
  if terminal_ok and raw_terminal then
    terminal_path_ignores = raw_terminal
  end

  local rules = {}
  if policy_cfg.rules ~= nil then
    if type(policy_cfg.rules) ~= 'table' then
      warn_once('[camouflage] invalid policy rules: rules must be a list')
    else
      for index, rule in ipairs(policy_cfg.rules) do
        local normalized = normalize_rule(rule, index)
        if normalized then
          table.insert(rules, normalized)
        end
      end
    end
  end

  return {
    enabled = enabled,
    default_action = default_action,
    terminal_path_ignores = terminal_path_ignores,
    rules = rules,
    active = enabled and (default_action ~= 'mask' or #terminal_path_ignores > 0 or #rules > 0),
  }
end

---@param filename string|nil
---@return string
local function start_dir_for_filename(filename)
  if not filename or filename == '' then
    return vim.fn.getcwd()
  end
  return vim.fn.fnamemodify(filename, ':p:h')
end

---@param filename string|nil
---@return string
function M.resolve_root(filename)
  local start_dir = start_dir_for_filename(filename)
  local project_filename = '.camouflage.yaml'
  local ok_config, config = pcall(require, 'camouflage.config')
  if ok_config then
    local cfg = config.get().project_config or {}
    project_filename = cfg.filename or project_filename
  end

  local project_file = vim.fn.findfile(project_filename, start_dir .. ';')
  if project_file ~= '' then
    return normalize_path(vim.fn.fnamemodify(project_file, ':p:h')):gsub('/+$', '')
  end

  local git_dir = vim.fn.finddir('.git', start_dir .. ';')
  if git_dir ~= '' then
    return normalize_path(vim.fn.fnamemodify(git_dir, ':p:h')):gsub('/+$', '')
  end

  return normalize_path(vim.fn.getcwd()):gsub('/+$', '')
end

---@param rule table
---@param ctx table
---@return boolean
local function rule_matches(rule, ctx)
  local var = ctx.variable or {}
  local value = tostring(var.value or '')

  if not any_glob_matches(ctx.relative_path or '', rule.path) then
    return false
  end
  if not any_glob_matches(ctx.basename or '', rule.basename) then
    return false
  end
  if not any_string_equals(rule.parser, ctx.parser_name or '') then
    return false
  end
  if not any_lua_pattern_matches(tostring(var.key or ''), rule.key, rule.key_exact) then
    return false
  end
  if rule.nested ~= nil and (var.is_nested == true) ~= rule.nested then
    return false
  end
  if rule.commented ~= nil and (var.is_commented == true) ~= rule.commented then
    return false
  end
  if rule.value_length then
    local length = #value
    if rule.value_length.min ~= nil and length < rule.value_length.min then
      return false
    end
    if rule.value_length.max ~= nil and length > rule.value_length.max then
      return false
    end
  end
  if not any_value_shape_matches(value, rule.value_shape) then
    return false
  end
  if not any_prefix_matches(value, rule.value_prefix) then
    return false
  end
  if not any_suffix_matches(value, rule.value_suffix) then
    return false
  end

  return true
end

---@param action string
---@param reason string
---@param rule table|nil
---@return table
local function decision(action, reason, rule)
  return {
    action = action,
    reason = reason,
    rule_id = rule and rule.id or nil,
  }
end

---@param ctx table
---@param compiled table
---@return table
local function evaluate_compiled(ctx, compiled)
  if not compiled.enabled then
    return decision('mask', 'policy_disabled')
  end

  local terminal_match = false
  for _, glob in ipairs(compiled.terminal_path_ignores) do
    if matches_compiled_glob(ctx.relative_path or '', glob.pattern) then
      terminal_match = true
      break
    end
  end

  if terminal_match then
    for _, rule in ipairs(compiled.rules) do
      if rule.action == 'mask' and rule.allow_force and rule_matches(rule, ctx) then
        return decision('mask', 'rule', rule)
      end
    end
    return decision('ignore', 'terminal_path_ignore')
  end

  local first_match = nil
  for _, rule in ipairs(compiled.rules) do
    if rule_matches(rule, ctx) then
      if rule.action == 'mask' and rule.allow_force then
        return decision('mask', 'rule', rule)
      end
      if not first_match then
        first_match = rule
        if rule.action == 'mask' then
          break
        end
      end
    end
  end

  if first_match then
    return decision(first_match.action, 'rule', first_match)
  end

  return decision(compiled.default_action, 'default')
end

---@param ctx table
---@param policy_cfg table|nil
---@return table
function M.evaluate(ctx, policy_cfg)
  ctx = vim.tbl_extend('force', {}, ctx or {})
  local filename = ctx.filename or ''
  ctx.root = ctx.root or M.resolve_root(filename)
  ctx.relative_path = ctx.relative_path or relative_path(filename, ctx.root)
  ctx.basename = ctx.basename or basename(filename)
  ctx.parser_name = ctx.parser_name or ctx.parser or ''

  local compiled = normalize_policy(policy_cfg)
  return evaluate_compiled(ctx, compiled)
end

---@param var table
---@param policy_decision table
---@return table
local function copy_with_policy(var, policy_decision)
  local copy = vim.tbl_extend('force', {}, var)
  copy.policy = vim.tbl_extend('force', {}, policy_decision)
  return copy
end

---@param opts table
---@return table[] filtered
---@return table result
function M.filter_variables(opts)
  opts = opts or {}
  local variables = opts.variables or {}
  local cfg = opts.config
  if not cfg then
    local ok_config, config = pcall(require, 'camouflage.config')
    if ok_config and opts.bufnr then
      cfg = config.get_for_buffer(opts.bufnr)
    elseif ok_config then
      cfg = config.get()
    else
      cfg = {}
    end
  end

  local compiled = normalize_policy((cfg or {}).policy)
  local filename = opts.filename or ''
  local root = opts.root or M.resolve_root(filename)
  local rel = relative_path(filename, root)
  local name = basename(filename)
  local parser_name = opts.parser_name or opts.parser or ''
  local filtered = {}
  local stats = {
    enabled = compiled.enabled,
    active = compiled.active,
    total = #variables,
    masked = 0,
    ignored = 0,
    terminal_path_ignored = 0,
    rule_ignored = 0,
    default_ignored = 0,
  }

  for _, var in ipairs(variables) do
    local policy_decision = evaluate_compiled({
      filename = filename,
      root = root,
      relative_path = rel,
      basename = name,
      parser_name = parser_name,
      variable = var,
    }, compiled)

    if policy_decision.action == 'ignore' then
      stats.ignored = stats.ignored + 1
      if policy_decision.reason == 'terminal_path_ignore' then
        stats.terminal_path_ignored = stats.terminal_path_ignored + 1
      elseif policy_decision.reason == 'rule' then
        stats.rule_ignored = stats.rule_ignored + 1
      elseif policy_decision.reason == 'default' then
        stats.default_ignored = stats.default_ignored + 1
      end
    else
      stats.masked = stats.masked + 1
      if opts.include_default_policy_metadata or policy_decision.reason ~= 'default' then
        table.insert(filtered, copy_with_policy(var, policy_decision))
      else
        table.insert(filtered, var)
      end
    end
  end

  log.debug(
    'policy file=%s parser=%s total=%d masked=%d ignored=%d terminal_ignored=%d',
    rel,
    parser_name,
    stats.total,
    stats.masked,
    stats.ignored,
    stats.terminal_path_ignored
  )

  return filtered, {
    stats = stats,
  }
end

return M
