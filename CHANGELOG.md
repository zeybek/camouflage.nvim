# Changelog

## [0.6.0](https://github.com/zeybek/camouflage.nvim/compare/v0.5.0...v0.6.0) (2026-02-13)


### Features

* **parsers:** add HCL/Terraform support ([73a2e4c](https://github.com/zeybek/camouflage.nvim/commit/73a2e4cd7bb72c69e5d7d9157bfc1f58029f71ca))

## [0.5.0](https://github.com/zeybek/camouflage.nvim/compare/v0.4.0...v0.5.0) (2026-02-13)


### Features

* extract TreeSitter queries to separate .scm files ([6c9cbc5](https://github.com/zeybek/camouflage.nvim/commit/6c9cbc588767f644e4019a3f92de633894a8afe9))

## [0.4.0](https://github.com/zeybek/camouflage.nvim/compare/v0.3.1...v0.4.0) (2026-02-13)


### Features

* add project config support with live reload ([#11](https://github.com/zeybek/camouflage.nvim/issues/11)) ([8ca84ec](https://github.com/zeybek/camouflage.nvim/commit/8ca84ec61db7178898924666e619521ae4a7fc04))

## [0.3.1](https://github.com/zeybek/camouflage.nvim/compare/v0.3.0...v0.3.1) (2026-02-11)


### Bug Fixes

* include custom_patterns in autocmd file patterns ([#9](https://github.com/zeybek/camouflage.nvim/issues/9)) ([ccaa940](https://github.com/zeybek/camouflage.nvim/commit/ccaa940ef0a0c3ba45eee1ab26953081b7ef3706))

## [0.3.0](https://github.com/zeybek/camouflage.nvim/compare/v0.2.0...v0.3.0) (2026-02-11)


### Features

* add .http file support and custom patterns API ([#7](https://github.com/zeybek/camouflage.nvim/issues/7)) ([62c5ff6](https://github.com/zeybek/camouflage.nvim/commit/62c5ff6419bf58a35aeef7c5045f8497f9b8f6ea))

## [0.2.0](https://github.com/zeybek/camouflage.nvim/compare/v0.1.0...v0.2.0) (2026-02-11)


### Features

* add CamouflageReveal command for temporary line reveal ([f58386b](https://github.com/zeybek/camouflage.nvim/commit/f58386b6a208f27e9c84c30a4e3332eac47f60f1))
* add CamouflageYank command to copy unmasked values ([5b8a262](https://github.com/zeybek/camouflage.nvim/commit/5b8a262ac50851cbd5c29a0cb55eeb1fde0bf8c6))
* add credentials file pattern for AWS credentials support ([8f0f49e](https://github.com/zeybek/camouflage.nvim/commit/8f0f49e0a3963ae2806dbd85d31fc91dd57fb0cb))
* add debug mode with logging for pcall errors ([d9188a5](https://github.com/zeybek/camouflage.nvim/commit/d9188a5e3e1a97e5ce3da778552c22b487164d4f))
* add event system with hooks for extensibility ([7339db6](https://github.com/zeybek/camouflage.nvim/commit/7339db6e23aad0c3ac016ed14e6589ea9916f37b))
* add Follow Cursor Mode for automatic line reveal ([bb97ed2](https://github.com/zeybek/camouflage.nvim/commit/bb97ed2e7aeb4335d7cd90168b55dd17c64783e6))
* add hot reload for config changes ([05a845e](https://github.com/zeybek/camouflage.nvim/commit/05a845ea090478fc1c67c194f216fb2add6e310b))
* add TreeSitter support for JSON, YAML, and TOML parsing ([f1cc6f7](https://github.com/zeybek/camouflage.nvim/commit/f1cc6f7cfde1296f2ad7d06d4fd954aadb7c975c))
* add XML parser for Maven/Spring config files ([a337e8f](https://github.com/zeybek/camouflage.nvim/commit/a337e8f8f004b5ebcc7243d6be097e9569139174))
* **pwned:** add check_on_change for real-time password checking ([9f5aa69](https://github.com/zeybek/camouflage.nvim/commit/9f5aa69403f2567a56ce2625ac06a063ef9454de))
* **pwned:** add Have I Been Pwned integration ([757953e](https://github.com/zeybek/camouflage.nvim/commit/757953ef536ee5cd3f4035499ca8a916f55cf262))
* **pwned:** enable auto_check and check_on_save by default ([ca736c3](https://github.com/zeybek/camouflage.nvim/commit/ca736c349968ea40511ac451ec2582844ac132aa))
* **pwned:** make pwned module work independently of camouflage toggle ([91bd2c5](https://github.com/zeybek/camouflage.nvim/commit/91bd2c5e0e8e6c954ae0e8cdea03b39797bdda88))
* **yaml:** add flow style support via TreeSitter ([eb16ea1](https://github.com/zeybek/camouflage.nvim/commit/eb16ea18e341cfd294c85ed9854608c8064fae3c))


### Bug Fixes

* **pwned:** correct field names to match parser output ([ca736c3](https://github.com/zeybek/camouflage.nvim/commit/ca736c349968ea40511ac451ec2582844ac132aa))
* **xml:** correct TreeSitter capture names for XML parsing ([7f408fe](https://github.com/zeybek/camouflage.nvim/commit/7f408fe8f45ce1b2b60b08aeb40fe8ba35546a9c))
* **yank:** use vim.uv/vim.loop shim for Neovim 0.9 compatibility ([8a52319](https://github.com/zeybek/camouflage.nvim/commit/8a523190b199fa9a0d700987ae0773f338785d3e))

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
