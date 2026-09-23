# Changelog

## [0.17.1](https://github.com/zeybek/camouflage.nvim/compare/v0.17.0...v0.17.1) (2026-09-23)


### Bug Fixes

* **init-command:** find the template in a LuaRocks install ([#180](https://github.com/zeybek/camouflage.nvim/issues/180)) ([9dc3a0d](https://github.com/zeybek/camouflage.nvim/commit/9dc3a0d92c0bc1c12f0beb161b928793eaa68a96))

## [0.17.0](https://github.com/zeybek/camouflage.nvim/compare/v0.16.1...v0.17.0) (2026-09-22)


### Features

* **http:** mask headers, query parameters and bodies in .http files ([#178](https://github.com/zeybek/camouflage.nvim/issues/178)) ([492f386](https://github.com/zeybek/camouflage.nvim/commit/492f38650da9f37e039da9fb88334ef414db0dfa))


### Bug Fixes

* **autocmds:** keep masking builtin formats when patterns is set ([#159](https://github.com/zeybek/camouflage.nvim/issues/159)) ([9a14b4d](https://github.com/zeybek/camouflage.nvim/commit/9a14b4d2c0ec24013262306e3e960aa0a3f87b30))
* **config:** keep values set at runtime across project config reloads ([#163](https://github.com/zeybek/camouflage.nvim/issues/163)) ([4499613](https://github.com/zeybek/camouflage.nvim/commit/449961369974a72727f388d853810a420cdfe9b5))
* **core:** give a window its wrap back when it leaves a masked buffer ([#176](https://github.com/zeybek/camouflage.nvim/issues/176)) ([7f68658](https://github.com/zeybek/camouflage.nvim/commit/7f68658a77bcb2d19588210e90d065997c2175fa))
* **env:** mask assignments behind readonly, declare, typeset and local ([#173](https://github.com/zeybek/camouflage.nvim/issues/173)) ([58e7e9a](https://github.com/zeybek/camouflage.nvim/commit/58e7e9af258d3f4b46e265cfb9ff8f475b569933))
* **env:** mask dotted and dashed keys in dotenv files ([#174](https://github.com/zeybek/camouflage.nvim/issues/174)) ([d232b94](https://github.com/zeybek/camouflage.nvim/commit/d232b949b84ceb81509d379a3fa8837dfe492e2a))
* **hcl:** mask values in one-line objects without the grammar ([#175](https://github.com/zeybek/camouflage.nvim/issues/175)) ([eee3923](https://github.com/zeybek/camouflage.nvim/commit/eee39233598aba7b19611ef45c40cda8f35131fd))
* **init:** keep highlight groups across colorschemes and user overrides ([#177](https://github.com/zeybek/camouflage.nvim/issues/177)) ([5a23f24](https://github.com/zeybek/camouflage.nvim/commit/5a23f24d8672a8c86ff39c609be09bf4e6800aeb))
* **init:** keep picker and completion guards across parser and config changes ([#161](https://github.com/zeybek/camouflage.nvim/issues/161)) ([6a17303](https://github.com/zeybek/camouflage.nvim/commit/6a1730367ffc60e3405603accbb37a81995e67d2))
* **picker:** hook pickers that load after camouflage ([#172](https://github.com/zeybek/camouflage.nvim/issues/172)) ([c68e1e8](https://github.com/zeybek/camouflage.nvim/commit/c68e1e8e6e3a995706bfbb4d971dcc8e5cc1b3da))
* **present:** mask buffers whose project config turns masking off ([#162](https://github.com/zeybek/camouflage.nvim/issues/162)) ([a0e7915](https://github.com/zeybek/camouflage.nvim/commit/a0e7915b282362e3300037237cdf38300d8ff3fe))
* **present:** refuse to turn masking off while presentation mode is on ([#166](https://github.com/zeybek/camouflage.nvim/issues/166)) ([368176a](https://github.com/zeybek/camouflage.nvim/commit/368176a9a424a54ad19c00ec76c58f7c28ea2b5f))
* **project-config:** warn when a project file can leave values unmasked ([#171](https://github.com/zeybek/camouflage.nvim/issues/171)) ([d051082](https://github.com/zeybek/camouflage.nvim/commit/d051082ffc088098a0029a143222117b9da5c45e))
* **yank:** clear pending registers when Neovim exits ([#168](https://github.com/zeybek/camouflage.nvim/issues/168)) ([8be63de](https://github.com/zeybek/camouflage.nvim/commit/8be63de9b0e3614a1a5f28f950363fbc0b177537))


### Performance Improvements

* **reveal:** stop reading the whole buffer once per value while a line is revealed ([#167](https://github.com/zeybek/camouflage.nvim/issues/167)) ([bcb6bb7](https://github.com/zeybek/camouflage.nvim/commit/bcb6bb73b2e53d131025f5a5aa141c153ab12070))

## [0.16.1](https://github.com/zeybek/camouflage.nvim/compare/v0.16.0...v0.16.1) (2026-09-18)


### Bug Fixes

* **install:** drop the wiki submodule that breaks lazy.nvim updates ([#142](https://github.com/zeybek/camouflage.nvim/issues/142)) ([5b9b27e](https://github.com/zeybek/camouflage.nvim/commit/5b9b27e34dc00531f9b7b5c37f87ad9a38991b30))

## [0.16.0](https://github.com/zeybek/camouflage.nvim/compare/v0.15.1...v0.16.0) (2026-09-18)


### Features

* **shield:** cover the whole editor until a key or a password ([#137](https://github.com/zeybek/camouflage.nvim/issues/137)) ([dfdaf9b](https://github.com/zeybek/camouflage.nvim/commit/dfdaf9bb88113365bd31bcb881c2c77c76fbb6c5))


### Bug Fixes

* **docs:** drop the duplicate :CamouflageAudit help tag ([#134](https://github.com/zeybek/camouflage.nvim/issues/134)) ([7d3452d](https://github.com/zeybek/camouflage.nvim/commit/7d3452d367c718e7733387995b42e67167de9973))

## [0.15.1](https://github.com/zeybek/camouflage.nvim/compare/v0.15.0...v0.15.1) (2026-09-18)


### Bug Fixes

* **terminal:** mask exported, commented and credential-URL lines ([#129](https://github.com/zeybek/camouflage.nvim/issues/129)) ([adc310d](https://github.com/zeybek/camouflage.nvim/commit/adc310dd371e8af5560771d3beb805c361e6bce9))

## [0.15.0](https://github.com/zeybek/camouflage.nvim/compare/v0.14.1...v0.15.0) (2026-09-18)


### Features

* **audit:** machine readable report and exit code ([#124](https://github.com/zeybek/camouflage.nvim/issues/124)) ([c0c5afe](https://github.com/zeybek/camouflage.nvim/commit/c0c5afe1ec696d6492e0eda3608d88c256f15b07))
* **health:** add :checkhealth camouflage ([#116](https://github.com/zeybek/camouflage.nvim/issues/116)) ([fde2ab8](https://github.com/zeybek/camouflage.nvim/commit/fde2ab8cd1c41eb1af1b46ae1f34eec040edba5d))
* **integrations:** mask values in diff and commit buffers ([#115](https://github.com/zeybek/camouflage.nvim/issues/115)) ([2161735](https://github.com/zeybek/camouflage.nvim/commit/2161735c20c4561b3e740747ddcc8a38df93b174))
* **integrations:** mask values in picker result rows ([#113](https://github.com/zeybek/camouflage.nvim/issues/113)) ([9590fe5](https://github.com/zeybek/camouflage.nvim/commit/9590fe5c83d78241012a56e6ec5da70bb2ae04de))
* **integrations:** mask values in quickfix and location list rows ([#114](https://github.com/zeybek/camouflage.nvim/issues/114)) ([9d7c2c9](https://github.com/zeybek/camouflage.nvim/commit/9d7c2c9860f0f1d9bd5007786ef49099b2e67334))
* **integrations:** support blink.cmp, fzf-lua and mini.pick ([#120](https://github.com/zeybek/camouflage.nvim/issues/120)) ([36134b3](https://github.com/zeybek/camouflage.nvim/commit/36134b3de03316beadcfab42d0041b9c8e630398))
* **policy:** let a rule choose the mask style for its keys ([#118](https://github.com/zeybek/camouflage.nvim/issues/118)) ([9a5c16e](https://github.com/zeybek/camouflage.nvim/commit/9a5c16e5a7f6be8adc0c90d139a968377da5d239))
* **present:** add presentation mode ([#122](https://github.com/zeybek/camouflage.nvim/issues/122)) ([f2298b8](https://github.com/zeybek/camouflage.nvim/commit/f2298b84581fb59e6ab6722b31fe579f20887be5))
* **registers:** list registers with masked values redacted ([#123](https://github.com/zeybek/camouflage.nvim/issues/123)) ([2172d83](https://github.com/zeybek/camouflage.nvim/commit/2172d83535f6b57e5386186955d1eb23b384bb26))
* **terminal:** opt-in masking for values printed in a terminal ([#121](https://github.com/zeybek/camouflage.nvim/issues/121)) ([f49af00](https://github.com/zeybek/camouflage.nvim/commit/f49af0055d9404da5c5d8408369b2ea4356c53ae))


### Bug Fixes

* **checks:** sync check anchors once per pass instead of per result ([#111](https://github.com/zeybek/camouflage.nvim/issues/111)) ([38c8361](https://github.com/zeybek/camouflage.nvim/commit/38c8361d7dfafb48c7b6a62d367e797c6d794cf6))


### Performance Improvements

* **checks:** reuse check answers for values that did not change ([#119](https://github.com/zeybek/camouflage.nvim/issues/119)) ([161a284](https://github.com/zeybek/camouflage.nvim/commit/161a2847aac4ee7e5412817f78e9aac40c48d2ee))

## [0.14.1](https://github.com/zeybek/camouflage.nvim/compare/v0.14.0...v0.14.1) (2026-09-16)


### Bug Fixes

* **core:** mask typed and pasted values before they are drawn ([#96](https://github.com/zeybek/camouflage.nvim/issues/96)) ([c736293](https://github.com/zeybek/camouflage.nvim/commit/c7362933e5972613fef62740f13c9e1fe9861795))

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
