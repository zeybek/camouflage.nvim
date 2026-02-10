rockspec_format = "3.0"
package = "camouflage.nvim"
version = "scm-1"

source = {
  url = "git+https://github.com/zeybek/camouflage.nvim.git",
}

description = {
  summary = "Hide sensitive values in configuration files during screen sharing",
  detailed = [[
    A Neovim plugin that visually masks sensitive values in configuration files
    (.env, .json, .yaml, .toml, .properties) during screen sharing using extmarks.
    The actual file content is never modified.
  ]],
  labels = { "neovim", "plugin", "security", "privacy" },
  homepage = "https://github.com/zeybek/camouflage.nvim",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  copy_directories = {
    "doc",
    "plugin",
  },
}
