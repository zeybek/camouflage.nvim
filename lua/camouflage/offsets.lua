---@mod camouflage.offsets Cumulative line byte offsets
---@brief [[
--- Leaf helper (no dependencies) for the 0-based byte offset at which each
--- 1-based line of a buffer/content starts. Used to convert TreeSitter
--- (row, col) ranges to byte offsets in O(1) instead of re-scanning the whole
--- content for every capture.
---@brief ]]

local M = {}

---@param lines string[]
---@return number[] offsets[i] = 0-based byte offset where 1-based line i starts
function M.from_lines(lines)
  local offsets = {}
  local current = 0
  for i, line in ipairs(lines) do
    offsets[i] = current
    current = current + #line + 1 -- +1 for the newline
  end
  offsets[#lines + 1] = current -- sentinel
  return offsets
end

---Same offsets directly from a content string, without allocating a lines table.
---@param content string
---@return number[] offsets[i] = 0-based byte offset where 1-based line i starts
function M.from_content(content)
  local offsets = { [1] = 0 }
  local pos = 1
  local line = 1
  while true do
    local nl = content:find('\n', pos, true)
    if not nl then
      break
    end
    line = line + 1
    -- The 1-based position of '\n' equals the 0-based start of the next line.
    offsets[line] = nl
    pos = nl + 1
  end
  return offsets
end

return M
