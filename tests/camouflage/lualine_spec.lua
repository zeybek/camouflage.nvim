describe('lualine.components.camouflage', function()
  local component
  local buffers = {}

  -- Minimal stand-in for lualine's component base class, so the component can be
  -- tested without lualine installed.
  local function stub_lualine_component()
    local Base = {}
    Base.__index = Base
    function Base:extend()
      local cls = setmetatable({}, { __index = self })
      cls.super = self
      return cls
    end
    function Base:init(options)
      self.options = options
    end
    package.loaded['lualine.component'] = Base
  end

  local function new_component(options)
    local instance = setmetatable({}, { __index = component })
    instance:init(options or {})
    return instance
  end

  local function enter_buffer(name, lines)
    local bufnr = vim.api.nvim_create_buf(true, false)
    table.insert(buffers, bufnr)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '/' .. name)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  before_each(function()
    stub_lualine_component()
    package.loaded['lualine.components.camouflage'] = nil
    component = require('lualine.components.camouflage')
    require('camouflage.config').setup({ project_config = { enabled = false } })
    require('camouflage.parsers').setup()
  end)

  after_each(function()
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
    package.loaded['lualine.component'] = nil
    package.loaded['lualine.components.camouflage'] = nil
  end)

  it('shows an icon with the default options', function()
    enter_buffer('status.env', { 'TOKEN=lualine-secret' })

    local status = new_component():update_status()

    assert.is_true(#status > 0)
    assert.equals(component.default_options.icon_enabled, status)
  end)

  it('uses the buffer-local enabled state', function()
    local bufnr = enter_buffer('disabled.env', { 'TOKEN=lualine-secret' })
    vim.b[bufnr].camouflage_enabled = false

    local icons = { icon_enabled = 'ON', icon_disabled = 'OFF' }
    local hidden = new_component(icons):update_status()
    local shown =
      new_component(vim.tbl_extend('force', icons, { show_disabled = true })):update_status()

    assert.equals('', hidden)
    assert.equals('OFF', shown)
  end)

  it('shows nothing for unsupported files', function()
    enter_buffer('notes.txt', { 'just text' })

    assert.equals('', new_component():update_status())
  end)
end)
