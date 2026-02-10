-- Minimal init for running tests

-- Add plenary to runtimepath
local plenary_path = vim.fn.stdpath('data') .. '/site/pack/vendor/start/plenary.nvim'
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:append(plenary_path)
end

-- Add plugin to runtimepath
local plugin_path = vim.fn.getcwd()
vim.opt.rtp:prepend(plugin_path)

-- Load plenary
vim.cmd('runtime plugin/plenary.vim')

-- Disable swap files
vim.opt.swapfile = false

-- Set up camouflage with defaults
require('camouflage').setup()
