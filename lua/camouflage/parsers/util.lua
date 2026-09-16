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

---Scan the items of an array literal (TOML/HCL style), which may span lines.
---Strings (double, single and triple quoted) are returned without quotes, bare
---scalars (numbers, booleans, references) as written. Nested arrays and
---inline tables/objects are skipped, and so are `#` and `//` comments.
---@param content string
---@param open_pos number 1-based position of the opening `[`
---@return {value: string, start_index: number, end_index: number, quoted: boolean}[] items 0-based, end-exclusive
---@return number|nil close_pos 1-based position of the closing `]`, nil if it never closes
function M.scan_array(content, open_pos)
  local items = {}
  local depth = 0
  local pos = open_pos + 1
  local len = #content

  local function add(start_pos, end_pos, quoted)
    if depth == 0 and end_pos >= start_pos then
      table.insert(items, {
        value = content:sub(start_pos, end_pos),
        start_index = start_pos - 1,
        end_index = end_pos,
        quoted = quoted,
      })
    end
  end

  while pos <= len do
    local char = content:sub(pos, pos)
    local triple = content:sub(pos, pos + 2)
    if triple == '"""' or triple == "'''" then
      local close = content:find(triple, pos + 3, true)
      if not close then
        return items, nil
      end
      add(pos + 3, close - 1, true)
      pos = close + 3
    elseif char == '"' or char == "'" then
      local close = char == '"' and M.find_unescaped(content, '"', pos + 1)
        or content:find("'", pos + 1, true)
      if not close then
        return items, nil
      end
      add(pos + 1, close - 1, true)
      pos = close + 1
    elseif char == '[' or char == '{' then
      depth = depth + 1
      pos = pos + 1
    elseif char == ']' or char == '}' then
      if depth == 0 then
        return items, char == ']' and pos or nil
      end
      depth = depth - 1
      pos = pos + 1
    elseif char == '#' or (char == '/' and content:sub(pos + 1, pos + 1) == '/') then
      local newline = content:find('\n', pos, true)
      if not newline then
        return items, nil
      end
      pos = newline
    elseif char:match('[%w_%-%+%.]') then
      local _, word_end = content:find('^[%w_%-%+%.:]+', pos)
      add(pos, word_end, false)
      pos = word_end + 1
    else
      pos = pos + 1
    end
  end

  return items, nil
end

---0-based row of a 0-based byte offset, given line start offsets from
---camouflage.offsets.from_content.
---@param offsets number[]
---@param index number
---@return number
function M.row_of(offsets, index)
  local lo, hi = 1, #offsets
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if offsets[mid] <= index then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return lo - 1
end

return M
