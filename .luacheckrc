std = "luajit"
cache = true

globals = {
  "vim",
}

read_globals = {
  "describe",
  "it",
  "before_each",
  "after_each",
  "assert",
  "pending",
}

ignore = {
  "212", -- Unused argument
  "631", -- Line too long
}

exclude_files = {
  "lua_modules/",
  ".luarocks/",
  ".tests/",
}

max_line_length = 120
