---@mod camouflage.project_config_watch Runtime watcher for project config

local M = {}
local GLOBAL_HANDLES_KEY = '__camouflage_project_config_watch_handles'

local log = require('camouflage.log')

-- Compatibility: vim.uv exists in Neovim 0.10+, vim.loop in 0.9
local uv = vim.uv or vim.loop

local augroup = vim.api.nvim_create_augroup('CamouflageProjectConfigWatch', { clear = true })
local watchers = {}
local warned_limit = false
local apply_fn = nil
local watched_filename = '.camouflage.yaml'

---@param tbl table|nil
local function cleanup_handles(tbl)
  if type(tbl) ~= 'table' then
    return
  end
  for _, entry in pairs(tbl) do
    if type(entry) == 'table' then
      if entry.timer then
        local ok, err = pcall(entry.timer.stop, entry.timer)
        if not ok then
          log.pcall_error('timer.stop', err)
        end
        ok, err = pcall(entry.timer.close, entry.timer)
        if not ok then
          log.pcall_error('timer.close', err)
        end
      end
      if entry.fs then
        local ok, err = pcall(entry.fs.stop, entry.fs)
        if not ok then
          log.pcall_error('fs.stop', err)
        end
        ok, err = pcall(entry.fs.close, entry.fs)
        if not ok then
          log.pcall_error('fs.close', err)
        end
      end
    end
  end
end

cleanup_handles(vim.g[GLOBAL_HANDLES_KEY])
vim.g[GLOBAL_HANDLES_KEY] = watchers

local status_state = {
  enabled = false,
  roots = {},
  root_count = 0,
  backend = 'auto',
  last_event_at = nil,
}

---@param root string
---@return boolean
local function has_root(root)
  return watchers[root] ~= nil
end

---@return number
local function watched_count()
  local count = 0
  for _ in pairs(watchers) do
    count = count + 1
  end
  return count
end

---@param root string
---@param filename string
---@return boolean
local function is_target_file_event(root, filename)
  if not filename or filename == '' then
    return true
  end
  local normalized = filename:gsub('\\', '/')
  if normalized == watched_filename then
    return true
  end
  local escaped = watched_filename:gsub('([^%w])', '%%%1')
  if normalized:match(escaped .. '$') then
    return true
  end
  local absolute = root:gsub('\\', '/') .. '/' .. watched_filename
  return normalized == absolute
end

---@param path string
---@return string
local function normalize(path)
  return vim.fn.fnamemodify(path, ':p')
end

---@param start_dir string
---@return string
local function resolve_root_from_dir(start_dir)
  local policy_file = vim.fn.findfile(watched_filename, start_dir .. ';')
  if policy_file ~= '' then
    return normalize(vim.fn.fnamemodify(policy_file, ':h'))
  end

  local git_dir = vim.fn.finddir('.git', start_dir .. ';')
  if git_dir ~= '' then
    return normalize(vim.fn.fnamemodify(git_dir, ':h'))
  end

  return normalize(vim.fn.getcwd())
end

---@param bufnr number
---@return string|nil
local function resolve_root_for_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local start_dir
  if name == '' then
    start_dir = vim.fn.getcwd()
  else
    start_dir = vim.fn.fnamemodify(name, ':p:h')
  end

  return resolve_root_from_dir(start_dir)
end

---@param root string
local function run_apply(root)
  status_state.last_event_at = os.time()

  if apply_fn then
    apply_fn(root)
  end
end

---@param root string
---@param debounce_ms number
local function schedule_apply(root, debounce_ms)
  if not watchers[root] then
    return
  end

  local entry = watchers[root]

  if entry.timer then
    local ok, err = pcall(entry.timer.stop, entry.timer)
    if not ok then
      log.pcall_error('timer.stop', err, { root = root })
    end
    ok, err = pcall(entry.timer.close, entry.timer)
    if not ok then
      log.pcall_error('timer.close', err, { root = root })
    end
    entry.timer = nil
  end

  if uv and uv.new_timer then
    local timer = uv.new_timer()
    entry.timer = timer
    timer:start(
      debounce_ms,
      0,
      vim.schedule_wrap(function()
        if timer and not timer:is_closing() then
          timer:stop()
          timer:close()
        end
        if watchers[root] then
          watchers[root].timer = nil
        end
        run_apply(root)
      end)
    )
  else
    vim.defer_fn(function()
      run_apply(root)
    end, debounce_ms)
  end
end

---@param root string
local function stop_root(root)
  local entry = watchers[root]
  if not entry then
    return
  end

  if entry.timer then
    local ok, err = pcall(entry.timer.stop, entry.timer)
    if not ok then
      log.pcall_error('timer.stop', err, { root = root })
    end
    ok, err = pcall(entry.timer.close, entry.timer)
    if not ok then
      log.pcall_error('timer.close', err, { root = root })
    end
  end

  if entry.fs then
    local ok, err = pcall(entry.fs.stop, entry.fs)
    if not ok then
      log.pcall_error('fs.stop', err, { root = root })
    end
    ok, err = pcall(entry.fs.close, entry.fs)
    if not ok then
      log.pcall_error('fs.close', err, { root = root })
    end
  end

  watchers[root] = nil
end

---@param root string
---@param cfg CamouflageProjectConfigLoaderConfig
local function add_root_watcher(root, cfg)
  if has_root(root) then
    return
  end

  local max_roots = cfg.max_watched_roots or 10
  if watched_count() >= max_roots then
    if not warned_limit then
      warned_limit = true
      log.warn('project config watcher limit reached (%d roots)', max_roots)
    end
    return
  end

  watchers[root] = { fs = nil, timer = nil }

  local backend = cfg.watch_backend or 'auto'
  if backend == 'auto' then
    backend = 'both'
  end

  if (backend == 'both' or backend == 'fs') and uv and uv.new_fs_event then
    local fs = uv.new_fs_event()
    local ok = fs
      and fs:start(
        root,
        {},
        vim.schedule_wrap(function(_, filename)
          if is_target_file_event(root, filename) then
            schedule_apply(root, cfg.watch_debounce_ms or 200)
          end
        end)
      )
    if ok then
      watchers[root].fs = fs
    elseif fs then
      local close_ok, err = pcall(fs.close, fs)
      if not close_ok then
        log.pcall_error('fs.close', err, { root = root })
      end
    end
  end
end

local function refresh_status()
  local roots = {}
  for root in pairs(watchers) do
    table.insert(roots, root)
  end
  table.sort(roots)
  status_state.roots = roots
  status_state.root_count = #roots
end

---Setup runtime watcher for .camouflage.yaml changes.
---@param callback fun(root: string)|nil
function M.setup(callback)
  apply_fn = callback
  local cfg = require('camouflage.config').get().project_config or {}
  watched_filename = cfg.filename or '.camouflage.yaml'

  if cfg.watch_enabled == false then
    M.stop()
    status_state.enabled = false
    status_state.backend = cfg.watch_backend or 'auto'
    refresh_status()
    return
  end

  status_state.enabled = true
  status_state.backend = cfg.watch_backend or 'auto'

  vim.api.nvim_clear_autocmds({ group = augroup })

  -- Track roots from active buffers lazily.
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufAdd' }, {
    group = augroup,
    callback = function(args)
      local root = resolve_root_for_buffer(args.buf)
      if root then
        add_root_watcher(root, cfg)
        refresh_status()
      end
    end,
  })

  local backend = cfg.watch_backend or 'auto'
  if backend == 'auto' then
    backend = 'both'
  end

  if backend == 'both' or backend == 'autocmd' then
    vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufDelete', 'BufNewFile' }, {
      group = augroup,
      pattern = { watched_filename, '*/' .. watched_filename },
      callback = function(args)
        local root = resolve_root_for_buffer(args.buf) or resolve_root_from_dir(vim.fn.getcwd())
        add_root_watcher(root, cfg)
        schedule_apply(root, cfg.watch_debounce_ms or 200)
        refresh_status()
      end,
    })
  end

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = augroup,
    callback = function()
      M.stop()
    end,
  })

  -- Prime root watchers for already loaded buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local root = resolve_root_for_buffer(bufnr)
      if root then
        add_root_watcher(root, cfg)
      end
    end
  end
  refresh_status()
end

function M.stop()
  for root in pairs(watchers) do
    stop_root(root)
  end
  warned_limit = false
  vim.api.nvim_clear_autocmds({ group = augroup })
  vim.g[GLOBAL_HANDLES_KEY] = watchers
  refresh_status()
end

---@return {enabled: boolean, backend: string, root_count: number, roots: string[], last_event_at: number|nil}
function M.status()
  refresh_status()
  return {
    enabled = status_state.enabled,
    backend = status_state.backend,
    root_count = status_state.root_count,
    roots = vim.deepcopy(status_state.roots),
    last_event_at = status_state.last_event_at,
  }
end

return M
