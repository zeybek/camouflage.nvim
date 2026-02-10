# camouflage.nvim

Hide sensitive values in configuration files during screen sharing.

A Neovim plugin that visually masks secrets in `.env`, `.json`, `.yaml`, `.toml`, and `.properties` files using extmarks - **without modifying the actual file content**.

[![Version](https://img.shields.io/github/v/release/zeybek/camouflage.nvim?style=flat&color=yellow)](https://github.com/zeybek/camouflage.nvim/releases)
[![CI](https://github.com/zeybek/camouflage.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/zeybek/camouflage.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-green?logo=neovim)](https://neovim.io)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Demo

![camouflage.nvim demo](assets/demo.gif)

## Features

- **Multi-format support**: `.env`, `.json`, `.yaml`, `.yml`, `.toml`, `.properties`, `.ini`, `.conf`, `.sh`
- **Nested key support**: Handles `database.connection.password` in JSON/YAML
- **All value types**: Masks strings, numbers, and booleans
- **Multiple styles**: `stars`, `dotted`, `text`, `scramble`
- **Telescope integration**: Mask values in preview buffers
- **Zero file modification**: All masking is purely visual

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'zeybek/camouflage.nvim',
  event = 'VeryLazy',
  opts = {},
  keys = {
    { '<leader>ct', '<cmd>CamouflageToggle<cr>', desc = 'Toggle Camouflage' },
  },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'zeybek/camouflage.nvim',
  config = function()
    require('camouflage').setup()
  end
}
```

## Configuration

```lua
require('camouflage').setup({
  -- General
  enabled = true,
  auto_enable = true,
  max_lines = 5000,            -- Skip files larger than this

  -- Appearance
  style = 'stars',           -- 'text' | 'dotted' | 'stars' | 'scramble'
  mask_char = '*',           -- Character for stars/dotted style
  mask_length = nil,         -- nil = actual length, number = fixed
  hidden_text = '************************',  -- For 'text' style
  highlight_group = 'Comment',

  -- Parser settings
  parsers = {
    include_commented = true,      -- Include commented lines (all parsers)
    env = {
      include_export = true,       -- Include export KEY=value
    },
    json = {
      max_depth = 10,              -- Maximum nesting depth
    },
    yaml = {
      max_depth = 10,              -- Maximum nesting depth
    },
  },

  -- Integrations
  integrations = {
    telescope = true,
    cmp = {
      disable_in_masked = true,
    },
  },
})
```

## Commands

| Command              | Description                      |
| -------------------- | -------------------------------- |
| `:CamouflageToggle`  | Toggle camouflage on/off         |
| `:CamouflageRefresh` | Refresh decorations              |
| `:CamouflageStatus`  | Show status and masked count     |

## Keymaps

Camouflage doesn't set any keymaps by default. Suggested:

```lua
vim.keymap.set('n', '<leader>ct', '<cmd>CamouflageToggle<cr>', { desc = 'Toggle Camouflage' })
```

## Supported File Formats

| Format      | Extensions                        | Nested Keys    |
| ----------- | --------------------------------- | -------------- |
| Environment | `.env`, `.env.*`, `.envrc`, `.sh` | No             |
| JSON        | `.json`                           | Yes            |
| YAML        | `.yaml`, `.yml`                   | Yes            |
| TOML        | `.toml`                           | Yes (sections) |
| Properties  | `.properties`, `.ini`, `.conf`    | Yes (sections) |

## API

```lua
local camouflage = require('camouflage')

-- Toggle
camouflage.toggle()

-- Enable/disable programmatically
camouflage.enable()
camouflage.disable()

-- Check status
camouflage.is_enabled()

-- Refresh decorations
camouflage.refresh()
```

## Lualine Integration

Camouflage provides a built-in lualine component:

```lua
require('lualine').setup({
  sections = {
    lualine_x = { 'camouflage' },
  },
})
```

With custom options:

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      {
        'camouflage',
        icon_enabled = '',    -- Icon when enabled (default)
        icon_disabled = '',   -- Icon when disabled
        show_disabled = false, -- Show icon when disabled
        show_count = false,    -- Show masked values count
      },
    },
  },
})
```

## Buffer-local Configuration

Override global settings for specific buffers using buffer variables:

```lua
-- Disable masking for current buffer
vim.b.camouflage_enabled = false

-- Use different style for current buffer
vim.b.camouflage_style = 'scramble'

-- Use different mask character
vim.b.camouflage_mask_char = '#'

-- Use fixed mask length
vim.b.camouflage_mask_length = 8

-- Use different highlight group
vim.b.camouflage_highlight_group = 'NonText'
```

Example autocommand for project-specific settings:

```lua
vim.api.nvim_create_autocmd('BufEnter', {
  pattern = '*/production/.env*',
  callback = function()
    vim.b.camouflage_style = 'scramble'
  end,
})
```

## Troubleshooting

### Masking not working

1. Check if the plugin is enabled:
   ```vim
   :CamouflageStatus
   ```

2. Verify the file type is supported:
   ```vim
   :echo expand('%:e')
   ```

3. Check if file exceeds `max_lines` (default: 5000):
   ```vim
   :echo line('$')
   ```

4. Ensure `setup()` was called:
   ```lua
   :lua print(require('camouflage').is_enabled())
   ```

### Values not being detected

1. For `.env` files, ensure proper format: `KEY=value` or `export KEY=value`
2. For YAML/JSON, check nesting depth isn't exceeded (default: 10)
3. Ensure values are not empty

### Performance issues

1. Reduce `max_lines` for large files:
   ```lua
   require('camouflage').setup({ max_lines = 1000 })
   ```

2. Disable `auto_enable` and toggle manually:
   ```lua
   require('camouflage').setup({ auto_enable = false })
   ```

### Telescope preview not masked

1. Ensure telescope integration is enabled (default: `true`):
   ```lua
   require('camouflage').setup({
     integrations = { telescope = true },
   })
   ```

2. Check if telescope.nvim is installed and loaded

### Buffer-local settings not applying

1. Set buffer variables before entering the buffer, or call `:CamouflageRefresh` after setting them
2. Check variable names: `vim.b.camouflage_enabled` (not `vim.b.camouflage.enabled`)

### Debug

View parsed variables:
```lua
:lua print(vim.inspect(require('camouflage.state').get_variables(0)))
```

View buffer state:
```lua
:lua print(vim.inspect(require('camouflage.state').get_buffer(0)))
```

For more help, see `:help camouflage` or report issues at [GitHub](https://github.com/zeybek/camouflage.nvim/issues).

## Also Available

- [Camouflage for VS Code](https://github.com/zeybek/camouflage) - The original VS Code extension

## License

MIT License - see [LICENSE](LICENSE) for details.
