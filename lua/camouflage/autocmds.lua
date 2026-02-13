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
        debounce_timers[args.buf] = vim.fn.timer_start(150, function()
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(args.buf) then
              core.apply_decorations(args.buf)
            end
          end)
          debounce_timers[args.buf] = nil
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufDelete', {
    group = group,
    callback = function(args)
      cleanup_timer(args.buf)
      cleanup_pwned_timer(args.buf)
      state.remove_buffer(args.buf)
    end,
  })

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
