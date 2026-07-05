---@mod camouflage.autocmds Autocommands

local M = {}

local state = require('camouflage.state')
local config = require('camouflage.config')
local parsers = require('camouflage.parsers')
local core = require('camouflage.core')

-- Timer storage for debouncing per buffer
local debounce_timers = {}
-- Separate timer storage for pwned debouncing
local pwned_debounce_timers = {}

---Clean up debounce timer for a buffer
---@param bufnr number Buffer number
---@return nil
local function cleanup_timer(bufnr)
  if debounce_timers[bufnr] then
    vim.fn.timer_stop(debounce_timers[bufnr])
    debounce_timers[bufnr] = nil
  end
end

---Clean up pwned debounce timer for a buffer
---@param bufnr number Buffer number
---@return nil
local function cleanup_pwned_timer(bufnr)
  if pwned_debounce_timers[bufnr] then
    vim.fn.timer_stop(pwned_debounce_timers[bufnr])
    pwned_debounce_timers[bufnr] = nil
  end
end

---Setup autocommands for automatic masking
---@return nil
function M.setup()
  local group = state.augroup
  vim.api.nvim_clear_autocmds({ group = group })

  local all_patterns = {}
  for _, pattern_config in ipairs(config.get().patterns) do
    local patterns = pattern_config.file_pattern
    if type(patterns) == 'string' then
      patterns = { patterns }
    end
    for _, p in ipairs(patterns) do
      table.insert(all_patterns, '*/' .. p)
      table.insert(all_patterns, p)
    end
  end

  -- Also include custom patterns in autocmds
  for _, pattern_config in ipairs(config.get().custom_patterns or {}) do
    local patterns = pattern_config.file_pattern
    if type(patterns) == 'string' then
      patterns = { patterns }
    end
    for _, p in ipairs(patterns) do
      table.insert(all_patterns, '*/' .. p)
      table.insert(all_patterns, p)
    end
  end

  -- Include file patterns from parsers registered at runtime via
  -- register_parser; without this their files never trigger auto-masking.
  for _, entry in ipairs(parsers.list()) do
    if entry.source == 'user' and entry.file_patterns then
      local patterns = entry.file_patterns
      if type(patterns) == 'string' then
        patterns = { patterns }
      end
      for _, p in ipairs(patterns) do
        table.insert(all_patterns, '*/' .. p)
        table.insert(all_patterns, p)
      end
    end
  end

  vim.api.nvim_create_autocmd({ 'BufEnter' }, {
    group = group,
    pattern = all_patterns,
    callback = function(args)
      if config.get().auto_enable and vim.api.nvim_buf_is_valid(args.buf) then
        state.init_buffer(args.buf)
        core.apply_decorations(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    group = group,
    pattern = all_patterns,
    callback = function(args)
      if config.is_enabled() and state.is_buffer_masked(args.buf) then
        cleanup_timer(args.buf)
        local debounce_ms = config.get().debounce_ms or 150
        if debounce_ms <= 0 then
          -- No debounce: apply immediately
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(args.buf) then
              core.apply_decorations(args.buf)
            end
          end)
        else
          debounce_timers[args.buf] = vim.fn.timer_start(debounce_ms, function()
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(args.buf) then
                core.apply_decorations(args.buf)
              end
            end)
            debounce_timers[args.buf] = nil
          end)
        end
      end
    end,
  })

  -- BufWipeout as well as BufDelete: unlisted preview buffers (telescope/snacks)
  -- get state via init_buffer but never fire BufDelete, so without BufWipeout
  -- their state leaks and a recycled bufnr could expose another file's values.
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      cleanup_timer(args.buf)
      cleanup_pwned_timer(args.buf)
      pcall(function()
        require('camouflage.checks.expiry').stop_auto_refresh(args.buf)
      end)
      -- Drop accumulated check results (pwned/expiry) so the per-line store does
      -- not grow without bound and a recycled bufnr never inherits stale badges.
      pcall(function()
        require('camouflage.checks').clear_buffer(args.buf)
      end)
      state.remove_buffer(args.buf)
    end,
  })

  -- Re-decorate buffers marked dirty by refresh_all when they are next shown,
  -- regardless of auto_enable, so a config change reaches hidden masked buffers.
  vim.api.nvim_create_autocmd({ 'BufWinEnter' }, {
    group = group,
    pattern = all_patterns,
    callback = function(args)
      if vim.api.nvim_buf_is_valid(args.buf) and state.is_dirty(args.buf) then
        core.apply_decorations(args.buf)
      end
    end,
  })

  -- Expiry auto-refresh timer: start when a maskable buffer is entered
  -- so 'expires in 2h' counts down without user action.
  local expiry_cfg = (config.get().checks or {}).expiry or {}
  if expiry_cfg.enabled ~= false then
    vim.api.nvim_create_autocmd('BufEnter', {
      group = group,
      pattern = all_patterns,
      callback = function(args)
        if vim.api.nvim_buf_is_valid(args.buf) then
          pcall(function()
            require('camouflage.checks.expiry').start_auto_refresh(args.buf)
          end)
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CamouflageConfigChanged',
    callback = function()
      core.refresh_all()
    end,
  })

  -- Pwned auto-check on BufEnter
  local cfg = config.get()
  local pwned_cfg = cfg.pwned or {}
  if pwned_cfg.enabled and pwned_cfg.auto_check then
    vim.api.nvim_create_autocmd('BufEnter', {
      group = group,
      pattern = all_patterns,
      desc = 'Camouflage pwned check on buffer enter',
      callback = function(args)
        if vim.api.nvim_buf_is_valid(args.buf) then
          vim.schedule(function()
            local pwned = require('camouflage.pwned')
            if pwned.is_available() then
              pwned.on_buf_enter(args.buf)
            end
          end)
        end
      end,
    })
  end

  -- Pwned check on save
  if pwned_cfg.enabled and pwned_cfg.check_on_save then
    vim.api.nvim_create_autocmd('BufWritePost', {
      group = group,
      pattern = all_patterns,
      desc = 'Camouflage pwned check on save',
      callback = function(args)
        if vim.api.nvim_buf_is_valid(args.buf) then
          vim.schedule(function()
            local pwned = require('camouflage.pwned')
            if pwned.is_available() then
              pwned.on_buf_write(args.buf)
            end
          end)
        end
      end,
    })
  end

  -- Pwned check on text change (debounced)
  if pwned_cfg.enabled and pwned_cfg.check_on_change then
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = group,
      pattern = all_patterns,
      desc = 'Camouflage pwned check on text change',
      callback = function(args)
        if vim.api.nvim_buf_is_valid(args.buf) then
          cleanup_pwned_timer(args.buf)
          -- Use 500ms debounce to avoid API spam during typing
          pwned_debounce_timers[args.buf] = vim.fn.timer_start(500, function()
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(args.buf) then
                local pwned = require('camouflage.pwned')
                if pwned.is_available() then
                  pwned.on_text_changed(args.buf)
                end
              end
            end)
            pwned_debounce_timers[args.buf] = nil
          end)
        end
      end,
    })
  end
end

---Disable all camouflage autocommands
---@return nil
function M.disable()
  vim.api.nvim_clear_autocmds({ group = state.augroup })
end

---Apply decorations to all currently loaded supported buffers
---@return nil
function M.apply_to_loaded_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local filename = vim.api.nvim_buf_get_name(bufnr)
      if filename ~= '' and parsers.is_supported(filename) and vim.api.nvim_buf_is_valid(bufnr) then
        state.init_buffer(bufnr)
        core.apply_decorations(bufnr)
      end
    end
  end
end

return M
