-- camouflage.nvim plugin entry point
-- This file is loaded automatically by Neovim

-- Prevent loading twice
if vim.g.loaded_camouflage then
  return
end
vim.g.loaded_camouflage = true

-- Check Neovim version
if vim.fn.has('nvim-0.9.0') ~= 1 then
  vim.notify('[camouflage] Requires Neovim 0.9.0 or later', vim.log.levels.ERROR)
  return
end

-- Lazy setup: don't load anything until setup() is called
-- The plugin will be fully initialized when the user calls require('camouflage').setup()
