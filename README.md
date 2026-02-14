# camouflage.nvim

Hide sensitive values in configuration files during screen sharing.

A Neovim plugin that visually masks secrets in `.env`, `.json`, `.yaml`, `.toml`, `.properties`, `.netrc`, `.xml`, `.http`, **Terraform/HCL** (`.tf`, `.tfvars`, `.hcl`), and **Dockerfile** files using extmarks - **without modifying the actual file content**.

[![Version](https://img.shields.io/github/v/release/zeybek/camouflage.nvim?style=flat&color=yellow)](https://github.com/zeybek/camouflage.nvim/releases)
[![CI](https://github.com/zeybek/camouflage.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/zeybek/camouflage.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-green?logo=neovim)](https://neovim.io)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/zeybek/camouflage.nvim)

## Demo

![camouflage.nvim demo](assets/demo.gif)

## Features

- **Multi-format support**: `.env`, `.json`, `.yaml`, `.yml`, `.toml`, `.properties`, `.ini`, `.conf`, `.sh`, `.netrc`, `.xml`, `.http`, `.tf`, `.tfvars`, `.hcl`, `Dockerfile`, `Containerfile`
- **Nested key support**: Handles `database.connection.password` in JSON/YAML/XML
- **All value types**: Masks strings, numbers, and booleans
- **Multiple styles**: `stars`, `dotted`, `text`, `scramble`
- **Reveal & Yank**: Temporarily reveal or copy masked values
- **Follow Cursor Mode**: Auto-reveal current line as you navigate
- **Have I Been Pwned**: Check passwords against breach database (Neovim 0.10+)
- **Hot Reload**: Config changes apply immediately
- **Event System**: Hooks for extending functionality
- **TreeSitter Support**: Enhanced parsing for JSON/YAML/TOML/XML/HTTP/HCL/Dockerfile
- **Telescope/Snacks Integration**: Mask values in preview buffers
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
    { '<leader>cr', '<cmd>CamouflageReveal<cr>', desc = 'Reveal Line' },
    { '<leader>cy', '<cmd>CamouflageYank<cr>', desc = 'Yank Value' },
    { '<leader>cf', '<cmd>CamouflageFollowCursor<cr>', desc = 'Follow Cursor' },
  },
}
```

<details>
<summary>Other package managers</summary>

#### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'zeybek/camouflage.nvim',
  config = function()
    require('camouflage').setup()
  end
}
```

#### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'zeybek/camouflage.nvim'

" In your init.lua or after/plugin/camouflage.lua:
lua require('camouflage').setup()
```

#### [mini.deps](https://github.com/echasnovski/mini.deps)

```lua
local add = MiniDeps.add
add({
  source = 'zeybek/camouflage.nvim',
})
require('camouflage').setup()
```

#### Manual Installation

```bash
git clone https://github.com/zeybek/camouflage.nvim.git \
  ~/.local/share/nvim/site/pack/plugins/start/camouflage.nvim
```

Then add to your `init.lua`:

```lua
require('camouflage').setup()
```

</details>

## Configuration

The plugin works with zero configuration. Here's a quick overview of common options:

```lua
require('camouflage').setup({
  enabled = true,
  auto_enable = true,
  style = 'stars',           -- 'text' | 'dotted' | 'stars' | 'scramble'
  mask_char = '*',
  debounce_ms = 150,
  max_lines = 5000,

  reveal = {
    follow_cursor = false,   -- Auto-reveal current line
  },

  yank = {
    confirm = true,          -- Require confirmation before copying
    auto_clear_seconds = 30, -- Auto-clear clipboard
  },

  integrations = {
    telescope = true,
    cmp = { disable_in_masked = true },
  },
})
```

> **[Full configuration reference](https://github.com/zeybek/camouflage.nvim/wiki/Configuration)** on the wiki.

## Commands

| Command | Description |
|---------|-------------|
| `:CamouflageToggle` | Toggle camouflage on/off |
| `:CamouflageReveal` | Reveal masked values on current line |
| `:CamouflageYank` | Copy unmasked value at cursor to clipboard |
| `:CamouflageFollowCursor` | Toggle follow cursor mode |
| `:CamouflageStatus` | Show status and masked count |
| `:CamouflageRefresh` | Refresh decorations |
| `:CamouflagePwnedCheck` | Check if value under cursor is pwned |
| `:CamouflagePwnedCheckBuffer` | Check all values in buffer |
| `:CamouflageInit` | Create `.camouflage.yaml` in project root |

> **[Full commands list](https://github.com/zeybek/camouflage.nvim/wiki/Commands-and-Keymaps)** on the wiki.

## Supported File Formats

| Format | Extensions | Nested Keys |
|--------|-----------|-------------|
| Environment | `.env`, `.env.*`, `.envrc`, `.sh` | No |
| JSON | `.json` | Yes |
| YAML | `.yaml`, `.yml` | Yes |
| TOML | `.toml` | Yes (sections) |
| Properties | `.properties`, `.ini`, `.conf`, `credentials` | Yes (sections) |
| Netrc | `.netrc`, `_netrc` | No |
| XML | `.xml` | Yes |
| HTTP | `.http` | No |
| HCL / Terraform | `.tf`, `.tfvars`, `.hcl` | Yes |
| Dockerfile | `Dockerfile`, `Containerfile`, `*.dockerfile` | No |

For unsupported formats, you can define [custom patterns](https://github.com/zeybek/camouflage.nvim/wiki/Custom-Patterns).

## Documentation

For detailed documentation, visit the **[Wiki](https://github.com/zeybek/camouflage.nvim/wiki)**:

- **[Getting Started](https://github.com/zeybek/camouflage.nvim/wiki/Getting-Started)** — Installation and first steps
- **[Configuration](https://github.com/zeybek/camouflage.nvim/wiki/Configuration)** — Full configuration reference
- **[Commands & Keymaps](https://github.com/zeybek/camouflage.nvim/wiki/Commands-and-Keymaps)** — All commands and suggested keybindings
- **[API Reference](https://github.com/zeybek/camouflage.nvim/wiki/API)** — Lua API for programmatic control
- **[Events & Hooks](https://github.com/zeybek/camouflage.nvim/wiki/Events-and-Hooks)** — Extend functionality with event listeners
- **[Have I Been Pwned](https://github.com/zeybek/camouflage.nvim/wiki/Have-I-Been-Pwned)** — Password breach checking
- **[Integrations](https://github.com/zeybek/camouflage.nvim/wiki/Integrations)** — Telescope, Snacks.nvim, nvim-cmp, Lualine
- **[Project Config](https://github.com/zeybek/camouflage.nvim/wiki/Project-Config)** — Repo-level `.camouflage.yaml`
- **[TreeSitter](https://github.com/zeybek/camouflage.nvim/wiki/TreeSitter)** — Custom TreeSitter queries
- **[Architecture](https://github.com/zeybek/camouflage.nvim/wiki/Architecture)** — Internal design and code flow
- **[Troubleshooting](https://github.com/zeybek/camouflage.nvim/wiki/Troubleshooting)** — Common issues and solutions

You can also use `:help camouflage` within Neovim.

## Also Available

- [Camouflage for VS Code](https://github.com/zeybek/camouflage) - The original VS Code extension

## License

MIT License - see [LICENSE](LICENSE) for details.
