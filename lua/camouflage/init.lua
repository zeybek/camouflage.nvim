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
  local snacks_ok, snacks = pcall(require, 'snacks')
  if not snacks_ok then
    return
  end

  local state = require('camouflage.state')
  local core = require('camouflage.core')
  local parsers = require('camouflage.parsers')

  local attached_buffers = {}
  local last_decorated = { buf = nil, file = nil }

  ---Extract filename from snacks picker item or window
  ---@param win number Window handle
  ---@return string|nil filename
  local function get_preview_filename(win)
    -- Method 1: Try to get from snacks picker's current item
    -- snacks.picker.get() returns an array of active pickers
    local pickers_ok, pickers = pcall(function()
      return snacks.picker.get()
    end)
    if pickers_ok and pickers and #pickers > 0 then
      -- Get the most recent picker (last in array)
      local picker = pickers[#pickers]
      if picker and picker.current then
        local item_ok, item = pcall(function()
          return picker:current()
        end)
        if item_ok and item then
          -- Item can have 'file', 'path', or 'filename' field
          local file = item.file or item.path or item.filename
          if file then
            -- If it's a relative path, make it absolute using cwd
            if not file:match('^/') then
              local cwd = (picker.opts and picker.opts.cwd) or item.cwd or vim.fn.getcwd()
              file = cwd .. '/' .. file
            end
            return file
          end
        end
      end
    end

    -- Method 2: Try buffer name (sometimes set for preview)
    local buf = vim.api.nvim_win_get_buf(win)
    local bufname = vim.api.nvim_buf_get_name(buf)
    if bufname and bufname ~= '' then
      return bufname
    end

    -- Method 3: Extract from window title (last resort)
    local ok, win_config = pcall(vim.api.nvim_win_get_config, win)
    if ok and win_config.title and type(win_config.title) == 'table' then
      for _, title_item in ipairs(win_config.title) do
        if type(title_item) == 'table' and type(title_item[1]) == 'string' then
          local text = title_item[1]:match('^%s*(.-)%s*$') -- trim
          -- Look for file-like patterns (contains . or /)
          if text:match('[%./]') and not text:match('^%d+/%d+$') then
            -- If relative, make absolute
            if not text:match('^/') then
              text = vim.fn.getcwd() .. '/' .. text
            end
            return text
          end
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
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    local filename = get_preview_filename(win)
    if not filename then
      return
    end

    -- Avoid redundant decoration of same buffer+file
    if last_decorated.buf == buf and last_decorated.file == filename then
      return
    end

    if not parsers.is_supported(filename) then
      return
    end

    if vim.api.nvim_buf_line_count(buf) > 1 then
      state.init_buffer(buf)
      core.apply_decorations(buf, filename)
      last_decorated.buf = buf
      last_decorated.file = filename
    end
  end

  ---Attach to a preview buffer to listen for content changes
  ---@param buf number Buffer handle
  ---@param win number Window handle
  local function attach_to_buffer(buf, win)
    if attached_buffers[buf] then
      -- Already attached, but still try to decorate (file might have changed)
      decorate_buffer(buf, win)
      return
    end
    attached_buffers[buf] = true

    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, bufnr)
        -- Reset last_decorated to allow re-decoration when content changes
        last_decorated.buf = nil
        last_decorated.file = nil
        vim.defer_fn(function()
          local preview_win = find_preview_window()
          if preview_win and vim.api.nvim_win_get_buf(preview_win) == bufnr then
            decorate_buffer(bufnr, preview_win)
          end
        end, 10)
      end,
      on_detach = function(_, bufnr)
        attached_buffers[bufnr] = nil
        if last_decorated.buf == bufnr then
          last_decorated.buf = nil
          last_decorated.file = nil
        end
      end,
    })

    decorate_buffer(buf, win)
  end

  -- Detect snacks picker and attach to preview buffer
  vim.api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter', 'WinEnter', 'CursorMoved' }, {
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
