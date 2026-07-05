---@mod camouflage.audit Workspace audit engine
---@brief [[
--- Scans files with the existing parser registry and returns redacted findings.
--- Audit never creates buffers, never applies extmarks, and never runs value
--- checks such as HIBP. Plaintext parser values are dropped before results are
--- returned or rendered.
---@brief ]]

local M = {}

local config = require('camouflage.config')
local log = require('camouflage.log')
local parsers = require('camouflage.parsers')
local position = require('camouflage.position')
local policy = require('camouflage.policy')

-- Compatibility: vim.uv exists in Neovim 0.10+, vim.loop in 0.9.
local uv = vim.uv or vim.loop

local DEFAULT_CHUNK_SIZE = 50

---@class CamouflageAuditConfig
---@field ignore_patterns? string[]
---@field max_files_per_chunk? integer
---@field destination? string
---@field open? boolean
---@field notify? boolean

---@class CamouflageAuditFinding
---@field filename string
---@field lnum integer 1-indexed line number
---@field col integer 1-indexed byte column
---@field end_col integer|nil 1-indexed end byte column
---@field key string
---@field parser string
---@field is_nested boolean
---@field is_commented boolean
---@field is_multiline boolean|nil
---@field value_length integer
---@field policy table|nil

---@class CamouflageAuditError
---@field filename string
---@field parser string|nil
---@field message string

---@class CamouflageAuditResult
---@field root string
---@field findings CamouflageAuditFinding[]
---@field errors CamouflageAuditError[]
---@field stats table
---@field cancelled boolean

---@class CamouflageAuditHandle
---@field result CamouflageAuditResult|nil
---@field cancel fun()
---@field is_cancelled fun(): boolean

---@param path string
---@return string
local function normalize_path(path)
  local normalized = vim.fn.fnamemodify(path, ':p'):gsub('\\', '/')
  if #normalized > 1 then
    normalized = normalized:gsub('/+$', '')
  end
  return normalized
end

---@param path string
---@return string
local function basename(path)
  return vim.fn.fnamemodify(path, ':t')
end

---@param path string
---@param root string
---@return string
local function relative_path(path, root)
  local rel = path:gsub('\\', '/')
  local normalized_root = root:gsub('\\', '/'):gsub('/+$', '')
  if rel == normalized_root then
    return basename(rel)
  end
  if rel:sub(1, #normalized_root + 1) == normalized_root .. '/' then
    rel = rel:sub(#normalized_root + 2)
  end
  return rel
end

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
---@param glob string
---@return boolean
local function glob_matches(text, glob)
  return text:gsub('\\', '/'):match(glob_to_pattern(glob)) ~= nil
end

---@param path string
---@param ignore_patterns string[]
---@return boolean
local function is_ignored(path, ignore_patterns)
  local normalized = path:gsub('\\', '/')
  local name = basename(normalized)

  for _, pattern in ipairs(ignore_patterns) do
    if pattern:find('/', 1, true) then
      if glob_matches(normalized, pattern) then
        return true
      end
    elseif parsers.match_pattern(name, pattern) or glob_matches(normalized, pattern) then
      return true
    end
  end

  return false
end

---@param opts table|nil
---@param base_config table|nil
---@return table
local function audit_config(opts, base_config)
  local cfg = (base_config or config.get()).audit or {}
  local audit_opts = opts or {}
  local merged = vim.tbl_deep_extend('force', {
    ignore_patterns = { '.git', '.git/**', 'node_modules', 'node_modules/**' },
    max_files_per_chunk = DEFAULT_CHUNK_SIZE,
    destination = 'quickfix',
    open = true,
    notify = true,
  }, cfg)

  if audit_opts.ignore_patterns then
    merged.ignore_patterns = audit_opts.ignore_patterns
  end
  if audit_opts.max_files_per_chunk then
    merged.max_files_per_chunk = audit_opts.max_files_per_chunk
  end
  if audit_opts.destination then
    merged.destination = audit_opts.destination
  end
  if audit_opts.open ~= nil then
    merged.open = audit_opts.open
  end
  if audit_opts.notify ~= nil then
    merged.notify = audit_opts.notify
  end

  return merged
end

---@param start_dir string
---@return string
local function resolve_root_from_dir(start_dir)
  local cfg = config.get().project_config or {}
  local project_config_filename = cfg.filename or '.camouflage.yaml'
  local project_file = vim.fn.findfile(project_config_filename, start_dir .. ';')
  if project_file ~= '' then
    return normalize_path(vim.fn.fnamemodify(project_file, ':h'))
  end

  local git_dir = vim.fn.finddir('.git', start_dir .. ';')
  if git_dir ~= '' then
    return normalize_path(vim.fn.fnamemodify(git_dir, ':h'))
  end

  return normalize_path(vim.fn.getcwd())
end

---@param bufnr number|nil
---@return string
function M.resolve_root(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= '' then
      return resolve_root_from_dir(vim.fn.fnamemodify(name, ':p:h'))
    end
  end
  return resolve_root_from_dir(vim.fn.getcwd())
end

---@param opts table
---@return string root
---@return string target
local function resolve_target(opts)
  local raw = opts.path or opts.root
  if not raw or raw == '' then
    local root = M.resolve_root(opts.bufnr)
    return root, root
  end

  local target = normalize_path(raw)
  local stat = uv and uv.fs_stat and uv.fs_stat(target) or nil
  if stat and stat.type == 'file' then
    return normalize_path(vim.fn.fnamemodify(target, ':h')), target
  end

  return target, target
end

---@param root string
---@return CamouflageAuditResult
local function new_result(root)
  return {
    root = root,
    findings = {},
    errors = {},
    cancelled = false,
    stats = {
      files_seen = 0,
      files_supported = 0,
      files_scanned = 0,
      files_skipped = 0,
      findings = 0,
      policy_ignored = 0,
      elapsed_ms = 0,
    },
  }
end

---@param result CamouflageAuditResult
---@param filename string
---@param parser_name string|nil
---@param message string
local function add_error(result, filename, parser_name, message)
  table.insert(result.errors, {
    filename = filename,
    parser = parser_name,
    message = message,
  })
end

---@param path string
---@param root string
---@param cfg table
---@param result CamouflageAuditResult
---@param files string[]
local function collect_files(path, root, cfg, result, files)
  local stat = uv and uv.fs_lstat and uv.fs_lstat(path) or (uv and uv.fs_stat and uv.fs_stat(path))
  if not stat then
    add_error(result, path, nil, 'failed to stat path')
    return
  end

  local rel = relative_path(path, root)
  if is_ignored(rel, cfg.ignore_patterns or {}) then
    result.stats.files_skipped = result.stats.files_skipped + 1
    return
  end

  if stat.type == 'file' then
    result.stats.files_seen = result.stats.files_seen + 1
    table.insert(files, path)
    return
  end

  if stat.type ~= 'directory' then
    result.stats.files_skipped = result.stats.files_skipped + 1
    return
  end

  local scanner = uv and uv.fs_scandir and uv.fs_scandir(path) or nil
  if not scanner then
    add_error(result, path, nil, 'failed to scan directory')
    return
  end

  while true do
    local name, entry_type = uv.fs_scandir_next(scanner)
    if not name then
      break
    end
    if name ~= '.' and name ~= '..' then
      local child = path .. '/' .. name
      if entry_type == 'link' then
        result.stats.files_skipped = result.stats.files_skipped + 1
      else
        collect_files(child, root, cfg, result, files)
      end
    end
  end
end

---@param target string
---@return table
local function new_discovery(target)
  return {
    done = false,
    stack = {
      { kind = 'path', path = target },
    },
  }
end

---@param state table
---@param root string
---@param cfg table
---@param result CamouflageAuditResult
---@param files string[]
local function discover_one(state, root, cfg, result, files)
  local frame = table.remove(state.stack)
  if not frame then
    state.done = true
    return
  end

  if frame.kind == 'scanner' then
    local name, entry_type = uv.fs_scandir_next(frame.scanner)
    if not name then
      return
    end

    table.insert(state.stack, frame)
    if name == '.' or name == '..' then
      return
    end

    if entry_type == 'link' then
      result.stats.files_skipped = result.stats.files_skipped + 1
    else
      table.insert(state.stack, { kind = 'path', path = frame.path .. '/' .. name })
    end
    return
  end

  local path = frame.path
  local stat = uv and uv.fs_lstat and uv.fs_lstat(path) or (uv and uv.fs_stat and uv.fs_stat(path))
  if not stat then
    add_error(result, path, nil, 'failed to stat path')
    return
  end

  local rel = relative_path(path, root)
  if is_ignored(rel, cfg.ignore_patterns or {}) then
    result.stats.files_skipped = result.stats.files_skipped + 1
    return
  end

  if stat.type == 'file' then
    result.stats.files_seen = result.stats.files_seen + 1
    table.insert(files, path)
    return
  end

  if stat.type ~= 'directory' then
    result.stats.files_skipped = result.stats.files_skipped + 1
    return
  end

  local scanner = uv and uv.fs_scandir and uv.fs_scandir(path) or nil
  if not scanner then
    add_error(result, path, nil, 'failed to scan directory')
    return
  end

  table.insert(state.stack, { kind = 'scanner', path = path, scanner = scanner })
end

---@param result CamouflageAuditResult
---@param var ParsedVariable
---@param filename string
---@param parser_name string
---@param lines string[]
---@param line_offsets number[]
local function add_finding(result, var, filename, parser_name, lines, line_offsets)
  if type(var) ~= 'table' or not var.key or not var.value then
    return
  end

  local start_pos = position.index_to_position(0, var.start_index or 0, lines, line_offsets)
  local end_pos =
    position.index_to_position(0, var.end_index or var.start_index or 0, lines, line_offsets)
  local lnum = (start_pos and start_pos.row + 1) or ((var.line_number or 0) + 1)
  local col = start_pos and (start_pos.col + 1) or 1
  local end_col = end_pos and (end_pos.col + 1) or nil

  table.insert(result.findings, {
    filename = filename,
    lnum = lnum,
    col = col,
    end_col = end_col,
    key = tostring(var.key),
    parser = parser_name,
    is_nested = var.is_nested == true,
    is_commented = var.is_commented == true,
    is_multiline = var.is_multiline == true or nil,
    value_length = #tostring(var.value),
    policy = var.policy and {
      action = var.policy.action,
      reason = var.policy.reason,
      rule_id = var.policy.rule_id,
    } or nil,
  })
  result.stats.findings = result.stats.findings + 1
end

---@param result CamouflageAuditResult
---@param filename string
---@param cfg table
local function process_file(result, filename, cfg)
  local parser, parser_name = parsers.find_parser_for_file(filename)
  if not parser then
    result.stats.files_skipped = result.stats.files_skipped + 1
    return
  end
  result.stats.files_supported = result.stats.files_supported + 1

  local ok_read, lines = pcall(vim.fn.readfile, filename)
  if not ok_read or type(lines) ~= 'table' then
    add_error(result, filename, parser_name, 'failed to read file')
    return
  end

  local max_lines = cfg.max_lines
  if max_lines and #lines > max_lines then
    result.stats.files_skipped = result.stats.files_skipped + 1
    return
  end

  local content = table.concat(lines, '\n')
  local ok_parse, variables = pcall(parser.parse, content, nil)
  if not ok_parse then
    add_error(result, filename, parser_name, 'parser failed')
    return
  end
  if type(variables) ~= 'table' then
    add_error(result, filename, parser_name, 'parser returned invalid result')
    return
  end

  result.stats.files_scanned = result.stats.files_scanned + 1
  local filtered_variables, policy_result = policy.filter_variables({
    filename = filename,
    root = result.root,
    parser_name = parser_name,
    variables = variables,
    config = cfg,
    include_default_policy_metadata = true,
  })
  result.stats.policy_ignored = result.stats.policy_ignored + policy_result.stats.ignored
  local line_offsets = position.compute_line_offsets(lines)
  for _, var in ipairs(filtered_variables) do
    add_finding(result, var, filename, parser_name, lines, line_offsets)
  end
end

---@param result CamouflageAuditResult
---@param started number
local function finish_result(result, started)
  result.stats.elapsed_ms = math.max(0, math.floor((vim.loop.hrtime() - started) / 1000000))
  log.debug(
    'audit root=%s seen=%d supported=%d scanned=%d skipped=%d findings=%d errors=%d elapsed_ms=%d',
    result.root,
    result.stats.files_seen,
    result.stats.files_supported,
    result.stats.files_scanned,
    result.stats.files_skipped,
    result.stats.findings,
    #result.errors,
    result.stats.elapsed_ms
  )
end

---@param opts table|nil
---@return CamouflageAuditResult
function M.run_sync(opts)
  opts = opts or {}
  local effective_config = config.get()
  local cfg = audit_config(opts, effective_config)
  local root, target = resolve_target(opts)
  local result = new_result(root)
  local started = vim.loop.hrtime()
  local files = {}

  collect_files(target, root, cfg, result, files)
  for _, filename in ipairs(files) do
    process_file(result, filename, effective_config)
  end

  finish_result(result, started)
  return result
end

---@param opts table|nil
---@return CamouflageAuditHandle
function M.run_async(opts)
  opts = opts or {}
  local effective_config = config.get()
  local cfg = audit_config(opts, effective_config)
  local root, target = resolve_target(opts)
  local result = new_result(root)
  local started = vim.loop.hrtime()
  local files = {}
  local discovery = new_discovery(target)
  local index = 1
  local cancelled = false
  local chunk_size = math.max(1, tonumber(cfg.max_files_per_chunk) or DEFAULT_CHUNK_SIZE)

  local handle = {
    result = nil,
  }

  function handle.cancel()
    cancelled = true
  end

  function handle.is_cancelled()
    return cancelled
  end

  local function complete()
    result.cancelled = cancelled
    finish_result(result, started)
    handle.result = result
    if opts.on_complete then
      opts.on_complete(result)
    end
  end

  local function step()
    if cancelled then
      complete()
      return
    end

    local phase = discovery.done and 'scan' or 'discover'
    local processed = 0

    while not discovery.done and processed < chunk_size do
      discover_one(discovery, root, cfg, result, files)
      processed = processed + 1
    end

    while discovery.done and index <= #files and processed < chunk_size do
      process_file(result, files[index], effective_config)
      index = index + 1
      processed = processed + 1
    end

    if opts.on_progress then
      opts.on_progress({
        phase = phase,
        root = root,
        files_total = #files,
        files_done = math.min(index - 1, #files),
        files_discovered = #files,
        files_scanned = result.stats.files_scanned,
        findings = result.stats.findings,
        errors = #result.errors,
      })
    end

    if discovery.done and index > #files then
      complete()
      return
    end

    vim.schedule(step)
  end

  vim.schedule(step)
  return handle
end

---@param opts table|nil
---@return CamouflageAuditResult|CamouflageAuditHandle
function M.run(opts)
  opts = opts or {}
  if opts.async or opts.on_complete then
    return M.run_async(opts)
  end
  return M.run_sync(opts)
end

---@param finding CamouflageAuditFinding
---@return string
local function finding_text(finding)
  return string.format('[%s] %s', finding.parser or 'unknown', finding.key or 'unknown')
end

---@param result CamouflageAuditResult
---@return table[]
function M.to_quickfix_items(result)
  local items = {}
  for _, finding in ipairs(result.findings or {}) do
    table.insert(items, {
      filename = finding.filename,
      lnum = finding.lnum,
      col = finding.col,
      end_col = finding.end_col,
      text = finding_text(finding),
      type = 'I',
    })
  end
  return items
end

---@param result CamouflageAuditResult
---@param opts table|nil
function M.set_list(result, opts)
  opts = opts or {}
  local cfg = audit_config(opts)
  local destination = opts.destination or cfg.destination or 'quickfix'
  local items = M.to_quickfix_items(result)
  local title = string.format('Camouflage Audit: %s', result.root)

  if destination == 'loclist' or destination == 'location' then
    vim.fn.setloclist(0, {}, 'r', { title = title, items = items })
    if cfg.open ~= false and #items > 0 then
      vim.cmd('lopen')
    end
  else
    vim.fn.setqflist({}, 'r', { title = title, items = items })
    if cfg.open ~= false and #items > 0 then
      vim.cmd('copen')
    end
  end
end

return M
