# Changelog

## [0.1.0](https://github.com/zeybek/camouflage.nvim/compare/v0.0.3...v0.1.0) (2026-02-10)


### Features

* add .netrc file support ([c1bf36a](https://github.com/zeybek/camouflage.nvim/commit/c1bf36a4b5246d5b1c9fc572f40240a4d225ff92))

## [0.0.3](https://github.com/zeybek/camouflage.nvim/compare/v0.0.2...v0.0.3) (2026-02-10)


### Features

* add custom colors support for masked text ([6880293](https://github.com/zeybek/camouflage.nvim/commit/6880293b5be8953503c630ccc30783e721efa845))

## [0.0.2](https://github.com/zeybek/camouflage.nvim/compare/v0.0.1...v0.0.2) (2026-02-10)


### Bug Fixes

* multiline YAML masking and snacks picker integration ([7a16b78](https://github.com/zeybek/camouflage.nvim/commit/7a16b78967795b2798fa2c2226d93da1655a1e2f))

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
