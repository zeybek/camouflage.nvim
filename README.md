# camouflage.nvim

Hide sensitive values in configuration files during screen sharing.

camouflage.nvim draws a mask over API keys, passwords and tokens in `.env`, JSON, YAML, TOML, Terraform, Dockerfiles and more, as the file opens. The file itself is never changed.

[![Version](https://img.shields.io/github/v/release/zeybek/camouflage.nvim?style=flat&color=yellow)](https://github.com/zeybek/camouflage.nvim/releases)
[![LuaRocks](https://img.shields.io/luarocks/v/zeybek/camouflage.nvim?style=flat&logo=lua&color=purple)](https://luarocks.org/modules/zeybek/camouflage.nvim)
[![CI](https://github.com/zeybek/camouflage.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/zeybek/camouflage.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-green?logo=neovim)](https://neovim.io)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/zeybek/camouflage.nvim)

![camouflage.nvim demo](assets/demo.gif)

A longer tour, with the audit, terminal masking and presentation mode, is on the [wiki](https://github.com/zeybek/camouflage.nvim/wiki).

## What it does

- Masks values as a file opens, in [10 formats](#supported-formats), with full key paths for nested values (`database.connection.password`)
- Covers a value you type, put or paste before Neovim draws it
- Lets you reveal a line on purpose, follow the cursor, or copy a value with a prompt and a timed clear
- Keeps values hidden where the file's text shows up elsewhere: Telescope, Snacks, fzf-lua and mini.pick previews and grep rows, quickfix lists, diffs and `git commit -v`, and `:terminal` output if you turn it on
- `:CamouflagePresent` masks everything and refuses reveals for the length of a demo, and `:CamouflageShield` covers the whole editor until you press a key
- Flags weak values offline (`[weak: default]`), shows when a JWT expires, and checks passwords against Have I Been Pwned when you ask it to
- `:CamouflageAudit` lists every masked key in a project, never the value, with JSON output and an exit code for CI
- Reads a per-project `.camouflage.yaml`, including data-only rules for what to mask and how

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'zeybek/camouflage.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  opts = {},
  keys = {
    { '<leader>mt', '<cmd>CamouflageToggle<cr>', desc = 'Toggle Camouflage' },
    { '<leader>mr', '<cmd>CamouflageReveal<cr>', desc = 'Reveal Line' },
    { '<leader>my', '<cmd>CamouflageYank<cr>', desc = 'Yank Value' },
    { '<leader>mf', '<cmd>CamouflageFollowCursor<cr>', desc = 'Follow Cursor' },
  },
}
```

`BufReadPre`/`BufNewFile` loads it as the first file opens, so no buffer is drawn before it's masked. The keys sit under `<leader>m` because LazyVim and AstroNvim already use `<leader>c`.

<details>
<summary>Other package managers</summary>

[rocks.nvim](https://github.com/lumen-oss/rocks.nvim), from [LuaRocks](https://luarocks.org/modules/zeybek/camouflage.nvim):

```vim
:Rocks install camouflage.nvim
```

[packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'zeybek/camouflage.nvim',
  config = function()
    require('camouflage').setup()
  end
}
```

[vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'zeybek/camouflage.nvim'
```

[mini.deps](https://github.com/echasnovski/mini.deps):

```lua
MiniDeps.add({ source = 'zeybek/camouflage.nvim' })
```

By hand:

```bash
git clone https://github.com/zeybek/camouflage.nvim.git \
  ~/.local/share/nvim/site/pack/plugins/start/camouflage.nvim
```

Everything except lazy.nvim's `opts` and packer's `config` also needs `require('camouflage').setup()` in your config.

</details>

## Usage

Open a supported file and its values are masked. These are the commands you'll use most:

| Command | What it does |
|---------|--------------|
| `:CamouflageToggle` | Turn masking on or off |
| `:CamouflageReveal` | Show the values on the current line until the cursor leaves it |
| `:CamouflageFollowCursor` | Keep the line under the cursor revealed as you move |
| `:CamouflageYank` | Copy the value under the cursor, after a prompt, and clear it after 30s |
| `:CamouflagePresent` | Presentation mode: everything masked, reveals refused (`!` to leave) |
| `:CamouflageShield` | Cover the whole editor until a key is pressed |
| `:CamouflageAudit` | List every masked key in the project in the quickfix list |
| `:CamouflageStatus` | Show whether this buffer is masked, by which parser, and how many values |

There are 22 in all, see [Commands and Keymaps](https://github.com/zeybek/camouflage.nvim/wiki/Commands-and-Keymaps). If a file isn't masked the way you expect, `:checkhealth camouflage` says why, without printing any value.

## Configuration

It works without any configuration. These are the options people change most, shown with their defaults:

```lua
require('camouflage').setup({
  style = 'stars',               -- 'stars' | 'dotted' | 'text' | 'scramble'
  reveal = { follow_cursor = false },
  yank = { confirm = true, auto_clear_seconds = 30 },
  terminal = { enabled = false },         -- mask KEY=value output in :terminal
  shield = { on_focus_lost = false },     -- cover the editor when it loses focus
  pwned = { auto_check = false },         -- Have I Been Pwned on BufEnter, sends a request
})
```

Every option is in the [Configuration](https://github.com/zeybek/camouflage.nvim/wiki/Configuration) reference and in `:help camouflage-configuration`.

## Security model

camouflage hides values visually, by drawing over them. It doesn't encrypt, remove or change anything, and the real text is still in the buffer. That covers the screen: screen sharing, pair programming, recordings and someone looking over your shoulder.

It doesn't cover anything that reads the buffer or the file:

- LSP servers, formatters, linters and AI assistants. nvim-cmp and blink.cmp are turned off in masked buffers, other completion sources aren't
- yanking with `yy` or `"+y`, the clipboard, and `:registers` (`:CamouflageYank` and `:CamouflageRegisters` are the careful versions)
- `:%print`, `:substitute` previews, saved files, backups, swap and undo files
- grep tools outside Neovim, and pickers camouflage has no integration for
- the message Neovim prints when it jumps to a quickfix entry, `(1 of 3): API_KEY=...`

`scramble` only shuffles the real characters, so it shows the value's length and character set. A `.camouflage.yaml` is data only. It can't run code or set the shield, and it can't turn on network checks unless you trust it. The [Security Model](https://github.com/zeybek/camouflage.nvim/wiki/Security-Model) page has the full list and the workarounds.

## Project config and policy

`:CamouflageInit` writes a `.camouflage.yaml` for the project. Rules in it, or in `setup()`, decide which found values are masked and how:

```yaml
version: 1
policy:
  terminal_path_ignores: ['tests/fixtures/**']
  rules:
    - id: ignore-debug
      action: ignore
      key: ['^DEBUG$', '^PORT$']
    - id: aws-key-id
      action: mask
      key: ['^AWS_ACCESS_KEY_ID$']
      style: partial
      show_end: 4
```

`AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE` then shows as `****************MPLE`. Key patterns are case-sensitive Lua patterns. See [Project Config](https://github.com/zeybek/camouflage.nvim/wiki/Project-Config) and [Rule Based Policy](https://github.com/zeybek/camouflage.nvim/wiki/Rule-Based-Policy).

## Audit in CI

```sh
nvim --headless -c 'CamouflageAudit --json=audit.json --quit .'
```

writes every finding (file, line, key, value length, policy decision) to `audit.json` and exits with 1 when there is one. No value is written anywhere. See [Workspace Audit](https://github.com/zeybek/camouflage.nvim/wiki/Workspace-Audit).

## Supported formats

| Format | Files | Nested keys |
|--------|-------|-------------|
| Environment | `.env`, `.env.*`, `*.env`, `.envrc`, `*.sh` | No |
| JSON | `*.json`, `*.jsonc` | Yes |
| YAML | `*.yaml`, `*.yml` | Yes |
| TOML | `*.toml` | Yes (sections) |
| Properties | `*.properties`, `*.ini`, `*.conf`, `credentials` | Yes (sections) |
| Netrc | `.netrc`, `_netrc` | No |
| XML | `*.xml` | Yes |
| HTTP | `*.http` | Yes (headers, query, JSON body) |
| HCL / Terraform | `*.tf`, `*.tfvars`, `*.hcl` | Yes |
| Dockerfile | `Dockerfile`, `Dockerfile.*`, `*.dockerfile`, `Containerfile`, `Containerfile.*` | No |

Formats with a TreeSitter grammar use it when it's installed, and every format works without it. For another format, add a Lua pattern with [`custom_patterns`](https://github.com/zeybek/camouflage.nvim/wiki/Custom-Patterns) or [register a parser](https://github.com/zeybek/camouflage.nvim/wiki/Custom-Parsers).

## Coming from cloak.nvim

The formats above need no patterns. Each one has a parser that finds values by their key, so there's nothing to write for them. The rest maps like this:

| cloak.nvim | camouflage.nvim |
|------------|-----------------|
| `cloak_character = '*'` | `mask_char = '*'` |
| `highlight_group = 'Comment'` | `highlight_group = 'Comment'` |
| `cloak_length = 8` | `mask_length = 8` |
| `cloak_telescope = true` | `integrations.telescope = true` (the default) |
| `patterns` for another file type | `custom_patterns` |
| `:CloakToggle` | `:CamouflageToggle` |
| `:CloakPreviewLine` | `:CamouflageReveal` |

Like cloak, it turns nvim-cmp off in masked buffers, and blink.cmp too.

## Documentation

The [wiki](https://github.com/zeybek/camouflage.nvim/wiki) has a page for every feature, and `:help camouflage` covers the same ground inside Neovim. Good places to start:

- [Getting Started](https://github.com/zeybek/camouflage.nvim/wiki/Getting-Started)
- [Commands and Keymaps](https://github.com/zeybek/camouflage.nvim/wiki/Commands-and-Keymaps)
- [Configuration](https://github.com/zeybek/camouflage.nvim/wiki/Configuration)
- [Integrations](https://github.com/zeybek/camouflage.nvim/wiki/Integrations)
- [Screen Shield](https://github.com/zeybek/camouflage.nvim/wiki/Screen-Shield)
- [API](https://github.com/zeybek/camouflage.nvim/wiki/API) and [Events and Hooks](https://github.com/zeybek/camouflage.nvim/wiki/Events-and-Hooks)
- [Troubleshooting](https://github.com/zeybek/camouflage.nvim/wiki/Troubleshooting)

## Also available

- [Camouflage for VS Code](https://github.com/zeybek/camouflage), the original extension

## License

MIT, see [LICENSE](LICENSE).
