-- Config used to record assets/demo.gif with vhs.
--
-- Self-contained: plugins are installed into a directory of their own, so it
-- never touches the recorder's own Neovim setup. Run it with:
--
--   vhs assets/demo.tape
--
-- or open it by hand with:
--
--   nvim -u assets/demo/init.lua assets/demo/project/.env

local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')
local root = vim.fn.fnamemodify(here, ':h:h')
local data = here .. '/.data'

vim.env.XDG_DATA_HOME = data
vim.env.XDG_STATE_HOME = data
vim.env.XDG_CACHE_HOME = data

local lazypath = data .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    '--branch=stable',
    'https://github.com/folke/lazy.nvim.git',
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = ' '
vim.opt.number = true
vim.opt.signcolumn = 'yes'
vim.opt.termguicolors = true
vim.opt.laststatus = 3
vim.opt.cmdheight = 1
vim.opt.showmode = false
vim.opt.swapfile = false
vim.opt.shortmess:append('I')

require('lazy').setup({
  root = data .. '/lazy',
  spec = {
    {
      'ellisonleao/gruvbox.nvim',
      priority = 1000,
      config = function()
        require('gruvbox').setup({ contrast = 'hard' })
        vim.cmd.colorscheme('gruvbox')
      end,
    },
    {
      'nvim-lualine/lualine.nvim',
      dependencies = { 'nvim-tree/nvim-web-devicons' },
      opts = {
        options = { theme = 'gruvbox', globalstatus = true, section_separators = '', component_separators = '' },
        sections = {
          lualine_a = { 'mode' },
          -- No branch component: the recording branch would end up in the GIF.
          lualine_b = {},
          lualine_c = { { 'filename', path = 1 } },
          lualine_x = { { 'camouflage', show_count = true } },
          lualine_y = { 'filetype' },
          lualine_z = { 'location' },
        },
      },
    },
    {
      'folke/snacks.nvim',
      priority = 900,
      lazy = false,
      opts = {
        picker = { enabled = true },
        bigfile = { enabled = false },
        quickfile = { enabled = false },
      },
    },
    {
      dir = root,
      name = 'camouflage.nvim',
      opts = {
        project_config = { enabled = false, watch_enabled = false },
        reveal = { notify = true },
        -- Off by default in the plugin; the demo turns it on to show it.
        terminal = { enabled = true },
      },
    },
  },
  install = { colorscheme = { 'gruvbox' } },
  change_detection = { enabled = false },
  ui = { backdrop = 100 },
})
