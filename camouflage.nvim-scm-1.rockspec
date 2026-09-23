rockspec_format = "3.0"
package = "camouflage.nvim"
version = "scm-1"

source = {
  url = "git+https://github.com/zeybek/camouflage.nvim.git",
}

description = {
  summary = "Hide sensitive values in configuration files during screen sharing",
  detailed = [[
    A Neovim plugin that visually masks sensitive values during screen sharing,
    using extmarks: .env, JSON, YAML, TOML, properties, netrc, XML, .http,
    Terraform/HCL and Dockerfiles, plus picker previews and result rows, the
    quickfix list, diffs and terminal output. It has a presentation mode and a
    screen shield. The actual file content is never modified.
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
  -- The builtin build installs everything under lua/ (the YAML template of
  -- :CamouflageInit included) next to the modules. The runtime directories
  -- outside lua/ must be listed here, or a LuaRocks install silently loses
  -- them: doc/, plugin/, queries/ (the TreeSitter .scm files) and schemas/.
  -- Never list lua/ or a directory under it: the .rock format uses that name.
  copy_directories = {
    "doc",
    "plugin",
    "queries",
    "schemas",
  },
}
