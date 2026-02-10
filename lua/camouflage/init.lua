---@mod camouflage Camouflage.nvim

local M = {}

-- x-release-please-start-version
M.version = '0.0.1'
-- x-release-please-end

local initialized = false

local function setup_cmp_integration()
  if not pcall(require, 'cmp') then
    return
  end

  local state = require('camouflage.state')
  local parsers = require('camouflage.parsers')

  vim.api.nvim_create_autocmd('BufEnter', {
    group = state.augroup,
    callback = function(args)
      local filename = vim.api.nvim_buf_get_name(args.buf)
      if parsers.is_supported(filename) and state.is_buffer_masked(args.buf) then
        require('cmp').setup.buffer({ enabled = false })
      end
    end,
  })
end

---Setup Telescope.nvim preview integration
local function setup_telescope_integration()
  if not pcall(require, 'telescope') then
    return
  end

  local state = require('camouflage.state')
  local core = require('camouflage.core')
  local parsers = require('camouflage.parsers')

  vim.api.nvim_create_autocmd('User', {
    group = state.augroup,
    pattern = 'TelescopePreviewerLoaded',
    callback = function(args)
      if not require('camouflage.config').is_enabled() then
        return
      end

      -- TelescopePreviewerLoaded is called within nvim_buf_call context,
      -- so nvim_get_current_buf() returns the preview buffer
      local bufnr = vim.api.nvim_get_current_buf()
      local filename = (args.data or {}).bufname or vim.api.nvim_buf_get_name(bufnr)

      if parsers.is_supported(filename) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            state.init_buffer(bufnr)
            core.apply_decorations(bufnr)
          end
        end)
      end
    end,
  })
end

---Setup Snacks.nvim picker preview integration
---Uses nvim_buf_attach to detect content changes in preview buffer
local function setup_snacks_integration()
  -- Only setup if snacks.nvim is available
  if not pcall(require, 'snacks') then
    return
  end

  local state = require('camouflage.state')
  local core = require('camouflage.core')
  local parsers = require('camouflage.parsers')

  local attached_buffers = {}

  ---Extract filename from snacks window title
  ---@param win number Window handle
  ---@return string|nil filename
  local function get_filename_from_title(win)
    local ok, win_config = pcall(vim.api.nvim_win_get_config, win)
    if not ok or not win_config.title or type(win_config.title) ~= 'table' then
      return nil
    end

    -- Snacks title format: { { " ", "hl" }, { "filename", "hl" }, ... }
    for _, item in ipairs(win_config.title) do
      if type(item) == 'table' and type(item[1]) == 'string' then
        local text = item[1]
        if text:match('%S') and text ~= 'Files' and text ~= 'Explorer' then
          return text
        end
      end
    end
    return nil
  end

  ---Find the snacks picker preview window
  ---@return number|nil win Window handle or nil
  local function find_preview_window()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local ok, is_preview = pcall(vim.api.nvim_win_get_var, win, 'snacks_picker_preview')
      if ok and is_preview then
        return win
      end
    end
    return nil
  end

  ---Apply decorations to a snacks preview buffer
  ---@param buf number Buffer handle
  ---@param win number Window handle
  local function decorate_buffer(buf, win)
    if not require('camouflage.config').is_enabled() then
      return
    end
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local filename = get_filename_from_title(win)
    if not filename or not parsers.is_supported(filename) then
      return
    end

    if vim.api.nvim_buf_line_count(buf) > 1 then
      state.init_buffer(buf)
      core.apply_decorations(buf, filename)
    end
  end

  ---Attach to a preview buffer to listen for content changes
  ---@param buf number Buffer handle
  ---@param win number Window handle
  local function attach_to_buffer(buf, win)
    if attached_buffers[buf] then
      return
    end
    attached_buffers[buf] = true

    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, bufnr)
        vim.defer_fn(function()
          local preview_win = find_preview_window()
          if preview_win and vim.api.nvim_win_get_buf(preview_win) == bufnr then
            decorate_buffer(bufnr, preview_win)
          end
        end, 10)
      end,
      on_detach = function(_, bufnr)
        attached_buffers[bufnr] = nil
      end,
    })

    decorate_buffer(buf, win)
  end

  -- Detect snacks picker and attach to preview buffer
  vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter', 'WinEnter' }, {
    group = state.augroup,
    callback = function()
      vim.defer_fn(function()
        local win = find_preview_window()
        if win then
          attach_to_buffer(vim.api.nvim_win_get_buf(win), win)
        end
      end, 20)
    end,
  })
end

local function setup_integrations()
  local config = require('camouflage.config').get()

  if config.integrations.cmp.disable_in_masked then
    setup_cmp_integration()
  end

  if config.integrations.telescope then
    setup_telescope_integration()
  end

  -- Snacks integration is always enabled (used by LazyVim and others)
  -- It only activates when snacks preview buffers are detected
  setup_snacks_integration()
end

---@param opts CamouflageConfig|nil
function M.setup(opts)
  if initialized then
    vim.notify('[camouflage] Already initialized', vim.log.levels.WARN)
    return
  end

  require('camouflage.config').setup(opts)
  require('camouflage.parsers').setup()

  local autocmds = require('camouflage.autocmds')
  autocmds.setup()

  require('camouflage.commands').setup()
  setup_integrations()
  autocmds.apply_to_loaded_buffers()

  initialized = true
end

function M.enable()
  require('camouflage.config').set('enabled', true)
  require('camouflage.core').refresh_all()
end

function M.disable()
  require('camouflage.config').set('enabled', false)
  local state = require('camouflage.state')
  local core = require('camouflage.core')

  for bufnr, _ in pairs(state.buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      core.clear_decorations(bufnr)
    end
  end
end

function M.toggle()
  if require('camouflage.config').is_enabled() then
    M.disable()
  else
    M.enable()
  end
end

function M.refresh()
  require('camouflage.core').refresh_all()
end

---@return boolean
function M.is_enabled()
  return require('camouflage.config').is_enabled()
end

return M
