# Changelog

## [0.14.0](https://github.com/zeybek/camouflage.nvim/compare/v0.13.0...v0.14.0) (2026-09-16)


### Features

* **core:** skip redundant decoration passes ([#94](https://github.com/zeybek/camouflage.nvim/issues/94)) ([83bcaf5](https://github.com/zeybek/camouflage.nvim/commit/83bcaf5164c42b9c8d727ac565d7ada08a1090b5))


### Bug Fixes

* **audit:** follow a symlink at the path the audit starts from ([#86](https://github.com/zeybek/camouflage.nvim/issues/86)) ([f2ac365](https://github.com/zeybek/camouflage.nvim/commit/f2ac365be0b21e2498a8f7b6461fc62a07d823b3))
* **autocmds:** mask values typed into buffers that had no values ([#72](https://github.com/zeybek/camouflage.nvim/issues/72)) ([eb8be33](https://github.com/zeybek/camouflage.nvim/commit/eb8be338a17ed41655586683d1a5f7aef5649263))
* **checks:** keep badges on their line when lines move ([#88](https://github.com/zeybek/camouflage.nvim/issues/88)) ([573b89c](https://github.com/zeybek/camouflage.nvim/commit/573b89c05ee2e82a9cdcd1deef416197ceb96581))
* **config:** clear the parser lookup cache when config changes ([#85](https://github.com/zeybek/camouflage.nvim/issues/85)) ([e41b9cf](https://github.com/zeybek/camouflage.nvim/commit/e41b9cf137c88c861f55d12e262d25afdb4527c5))
* **config:** resolve project config per repository ([#79](https://github.com/zeybek/camouflage.nvim/issues/79)) ([4756a50](https://github.com/zeybek/camouflage.nvim/commit/4756a500bba4a91dcff33a892c9802834992b8a1))
* **core:** keep masks in place until new ones are set ([#90](https://github.com/zeybek/camouflage.nvim/issues/90)) ([277cd1b](https://github.com/zeybek/camouflage.nvim/commit/277cd1bb9549e6ca256406e4412f2d03763e2953))
* **dockerfile:** mask each pair at its own position and follow continuation lines ([#80](https://github.com/zeybek/camouflage.nvim/issues/80)) ([c66ae1b](https://github.com/zeybek/camouflage.nvim/commit/c66ae1b521aabff56d371f78a12db7288e523f72))
* **env:** mask multiline quoted values ([#74](https://github.com/zeybek/camouflage.nvim/issues/74)) ([bdfc7f6](https://github.com/zeybek/camouflage.nvim/commit/bdfc7f636687853a2ce8a2c305e96d892d36f902))
* **init:** stop the project template from replacing default lists ([#91](https://github.com/zeybek/camouflage.nvim/issues/91)) ([0727d4c](https://github.com/zeybek/camouflage.nvim/commit/0727d4c580ffb6b41305f2737e2356cff64b72e3))
* **lualine:** show default icons and follow the buffer's masking state ([#92](https://github.com/zeybek/camouflage.nvim/issues/92)) ([925d96e](https://github.com/zeybek/camouflage.nvim/commit/925d96e67cc9cbdcf98179503727f4d7e867e2b4))
* **parsers:** mask values inside arrays and lists ([#77](https://github.com/zeybek/camouflage.nvim/issues/77)) ([6af376a](https://github.com/zeybek/camouflage.nvim/commit/6af376a6515f1109ab6194ed6973986ffb91e7dd))
* **parsers:** match file patterns as real globs ([#84](https://github.com/zeybek/camouflage.nvim/issues/84)) ([70103d3](https://github.com/zeybek/camouflage.nvim/commit/70103d34f22e04598229316e7e3442f18f339b58))
* **project_config:** keep untrusted files from enabling network checks ([#78](https://github.com/zeybek/camouflage.nvim/issues/78)) ([0eb08d8](https://github.com/zeybek/camouflage.nvim/commit/0eb08d87ea0bf82e130cbd856b9853e3e0a395f5))
* **properties:** support java separators, escaped keys and continuation lines ([#83](https://github.com/zeybek/camouflage.nvim/issues/83)) ([e87435b](https://github.com/zeybek/camouflage.nvim/commit/e87435b874295fae3b0bf3794d5881c522e854ef))
* **pwned:** skip values the masking policy ignores ([#89](https://github.com/zeybek/camouflage.nvim/issues/89)) ([0b99f35](https://github.com/zeybek/camouflage.nvim/commit/0b99f353a523983ab2689e78e8f3224f558c2924))
* **toml:** mask quoted keys with = and multi-line strings ([#81](https://github.com/zeybek/camouflage.nvim/issues/81)) ([e3111cb](https://github.com/zeybek/camouflage.nvim/commit/e3111cbac2cb2b6566a97286399a10ac9eff6ea3))
* **treesitter:** mask hcl values when the grammar is installed ([#75](https://github.com/zeybek/camouflage.nvim/issues/75)) ([516edc5](https://github.com/zeybek/camouflage.nvim/commit/516edc5e4e0f632f3780c0b33b8861241ee84fc6))
* **weak_secret:** only match placeholder words as whole words ([#93](https://github.com/zeybek/camouflage.nvim/issues/93)) ([ff4a47e](https://github.com/zeybek/camouflage.nvim/commit/ff4a47ed96e127dcdbceea743eb6136d9eec6ac8))
* **xml:** mask element text with attributes, entities and CDATA ([#76](https://github.com/zeybek/camouflage.nvim/issues/76)) ([7b670d0](https://github.com/zeybek/camouflage.nvim/commit/7b670d04775943b64e3274d1c90576410163a681))
* **yaml:** mask values under quoted, digit-leading and spaced keys ([#82](https://github.com/zeybek/camouflage.nvim/issues/82)) ([889c66d](https://github.com/zeybek/camouflage.nvim/commit/889c66dcfa02ade7bd80c995374f15a46ff044cc))
* **yank:** clean up uppercase registers after auto-clear ([#87](https://github.com/zeybek/camouflage.nvim/issues/87)) ([601c143](https://github.com/zeybek/camouflage.nvim/commit/601c143c990acc909b05a7226fc80b12eaba1b5c))

## [0.13.0](https://github.com/zeybek/camouflage.nvim/compare/v0.12.2...v0.13.0) (2026-09-05)


### Features

* **json:** add native JSONC (*.jsonc) support ([#48](https://github.com/zeybek/camouflage.nvim/issues/48)) ([022f66e](https://github.com/zeybek/camouflage.nvim/commit/022f66ef986236530d249fbef5fc37c523034fc6)), closes [#47](https://github.com/zeybek/camouflage.nvim/issues/47)

## [0.12.2](https://github.com/zeybek/camouflage.nvim/compare/v0.12.1...v0.12.2) (2026-07-06)


### Bug Fixes

* handle multiline masking and parser ranges ([#44](https://github.com/zeybek/camouflage.nvim/issues/44)) ([930b2d0](https://github.com/zeybek/camouflage.nvim/commit/930b2d0b0d9605af8f82487c928697bd43e9330a))

## [0.12.1](https://github.com/zeybek/camouflage.nvim/compare/v0.12.0...v0.12.1) (2026-07-05)


### Bug Fixes

* **core:** clear state on global disable ([#37](https://github.com/zeybek/camouflage.nvim/issues/37)) ([3cb3621](https://github.com/zeybek/camouflage.nvim/commit/3cb3621b0932aee11393e499d5e7e1005c15ebac))
* **core:** reset mask state on no-mask paths ([#36](https://github.com/zeybek/camouflage.nvim/issues/36)) ([56d6572](https://github.com/zeybek/camouflage.nvim/commit/56d6572fc6d5c2f67962229061d1447496e47b8b))
* **core:** use buffer-local mask config ([#39](https://github.com/zeybek/camouflage.nvim/issues/39)) ([a90ff1c](https://github.com/zeybek/camouflage.nvim/commit/a90ff1c9e378c742aa2fb725241236f6fa4a86a2))
* **init:** mask loaded buffers during setup ([#34](https://github.com/zeybek/camouflage.nvim/issues/34)) ([6ea668a](https://github.com/zeybek/camouflage.nvim/commit/6ea668a0693bcd889e8b9bbba832aec60d889589))
* **json:** preserve fallback paths for duplicate values ([#42](https://github.com/zeybek/camouflage.nvim/issues/42)) ([79fb4c4](https://github.com/zeybek/camouflage.nvim/commit/79fb4c4c934a18c4ae328349eeaad86a9a8825a0))
* **position:** honor end-exclusive cursor bounds ([#43](https://github.com/zeybek/camouflage.nvim/issues/43)) ([7c4105c](https://github.com/zeybek/camouflage.nvim/commit/7c4105c6024a9c4511c9518c42e0db82bf338429))
* **pwned:** make HIBP auto checks opt-in ([#38](https://github.com/zeybek/camouflage.nvim/issues/38)) ([877e745](https://github.com/zeybek/camouflage.nvim/commit/877e745121af5ca2896b96da776f442687672a62))

## [0.12.0](https://github.com/zeybek/camouflage.nvim/compare/v0.11.0...v0.12.0) (2026-07-05)


### Features

* add public check API ([#32](https://github.com/zeybek/camouflage.nvim/issues/32)) ([cb314ce](https://github.com/zeybek/camouflage.nvim/commit/cb314ce5326773951ee15152e2df7048900e7e2c))

## [0.11.0](https://github.com/zeybek/camouflage.nvim/compare/v0.10.1...v0.11.0) (2026-07-05)


### Features

* add rule-based masking policy ([aef052a](https://github.com/zeybek/camouflage.nvim/commit/aef052a242e643ddfad5b01eef415bcd9b90f59a))
* add weak secret check ([#30](https://github.com/zeybek/camouflage.nvim/issues/30)) ([2849422](https://github.com/zeybek/camouflage.nvim/commit/284942268c63dbb67daea9d2d8f61f43767ab6cc))
* add workspace secret audit ([#28](https://github.com/zeybek/camouflage.nvim/issues/28)) ([003665e](https://github.com/zeybek/camouflage.nvim/commit/003665e724e5b4d4ffaaad890cd06fc95146d3f7))

## [0.10.1](https://github.com/zeybek/camouflage.nvim/compare/v0.10.0...v0.10.1) (2026-07-04)


### Bug Fixes

* remediate review findings ([#26](https://github.com/zeybek/camouflage.nvim/issues/26)) ([ed34c54](https://github.com/zeybek/camouflage.nvim/commit/ed34c54e6d34f45bf3f99cb8a89688f509c5529a))

## [0.10.0](https://github.com/zeybek/camouflage.nvim/compare/v0.9.0...v0.10.0) (2026-06-10)


### Features

* audit remediation — security, correctness, performance & infra hardening ([a78a823](https://github.com/zeybek/camouflage.nvim/commit/a78a823560ade76ecfb15adaed3816d8f869d798))

## [0.9.0](https://github.com/zeybek/camouflage.nvim/compare/v0.8.0...v0.9.0) (2026-05-12)


### Features

* **checks:** add JWT expiry hints and centralized badges renderer ([#22](https://github.com/zeybek/camouflage.nvim/issues/22)) ([56f9658](https://github.com/zeybek/camouflage.nvim/commit/56f9658952478c76ffc160179cc981926d33deca))

## [0.8.0](https://github.com/zeybek/camouflage.nvim/compare/v0.7.1...v0.8.0) (2026-05-11)


### Features

* **parsers:** add public API for registering custom parsers ([#20](https://github.com/zeybek/camouflage.nvim/issues/20)) ([dba809b](https://github.com/zeybek/camouflage.nvim/commit/dba809b12777196807c54da8ef2d1b20c8ef71a2))

## [0.7.1](https://github.com/zeybek/camouflage.nvim/compare/v0.7.0...v0.7.1) (2026-04-19)


### Bug Fixes

* align pwned virtual text config keys ([#18](https://github.com/zeybek/camouflage.nvim/issues/18)) ([28a3614](https://github.com/zeybek/camouflage.nvim/commit/28a3614766f877971a27e509566b4924a6b2b32f))

## [0.7.0](https://github.com/zeybek/camouflage.nvim/compare/v0.6.0...v0.7.0) (2026-02-14)


### Features

* **config:** add debounce_ms option for masking delay control ([adc725a](https://github.com/zeybek/camouflage.nvim/commit/adc725a80a6affc39a81111d904538f72f03a142))
* **parsers:** add Dockerfile/Containerfile support ([92436e1](https://github.com/zeybek/camouflage.nvim/commit/92436e10e99653811c4d497934b8c913ab981f3a))

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
