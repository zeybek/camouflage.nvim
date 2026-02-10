---@mod camouflage.autocmds Autocommands

local M = {}

local state = require('camouflage.state')
local config = require('camouflage.config')
local parsers = require('camouflage.parsers')
local core = require('camouflage.core')

-- Timer storage for debouncing per buffer
local debounce_timers = {}

---@param bufnr number
local function cleanup_timer(bufnr)
  if debounce_timers[bufnr] then
    vim.fn.timer_stop(debounce_timers[bufnr])
    debounce_timers[bufnr] = nil
  end
end

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
end

function M.disable()
  vim.api.nvim_clear_autocmds({ group = state.augroup })
end

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
