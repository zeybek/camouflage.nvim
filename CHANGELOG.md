# Changelog

## [0.0.1](https://github.com/zeybek/camouflage.nvim/releases/tag/v0.0.1) (2026-02-10)

### Features

* Initial release
* Multi-format support: `.env`, `.json`, `.yaml`, `.toml`, `.properties`
* Multiple masking styles: `stars`, `dotted`, `text`, `scramble`
* Telescope preview integration
* Snacks.nvim picker integration
* nvim-cmp integration (disable completion in masked buffers)
* Lualine component with optional masked count display
* Buffer-local configuration support
* Commands: `CamouflageToggle`, `CamouflageRefresh`, `CamouflageStatus`
* Performance optimizations: debounce timer, max_lines protection
