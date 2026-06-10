---@mod camouflage.parsers.util Shared parser helpers

local M = {}

---Find the first `char` at or after `init` that is NOT backslash-escaped.
---A backslash escapes the next byte (so `\"` is skipped), which is how quoted
---strings terminate in TOML basic strings, HCL, and Dockerfile values. Returns
---the 1-based position of the terminator, or nil.
---@param s string
---@param char string Single terminator character
---@param init number|nil 1-based start position (default 1)
---@return number|nil
function M.find_unescaped(s, char, init)
  local pos = init or 1
  while pos <= #s do
    local c = s:sub(pos, pos)
    if c == '\\' then
      pos = pos + 2 -- skip the escaped byte
    elseif c == char then
      return pos
    else
      pos = pos + 1
    end
  end
  return nil
end

return M
