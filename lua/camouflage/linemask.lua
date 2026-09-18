---@mod camouflage.linemask Line-level value matching

-- Finding a value without parsing the file around it. Used where the structure
-- isn't available: rows changed inside `on_lines`, and text drawn by another
-- plugin (picker rows and the like) where all we have is one line.
--
-- It errs towards masking: a line that looks like `key = value` is treated as
-- one, even when the real parser would have left that value alone.

local M = {}

local styles = require('camouflage.styles')

-- Each pattern captures the position right after the separator and any opening
-- quote, so the capture is where the value starts.
local VALUE_START_PATTERNS = {
  -- KEY=value, export KEY=value, # KEY=value, key: value, - key: value
  '^%s*[#;]*%s*export%s+[%w_.%-]+%s*=%s*["\']?()',
  '^%s*[#;]*%s*%-?%s*["\']?[%w_.%-]+["\']?%s*[=:]%s*["\']?()',
  -- "any key": value
  '^%s*%-?%s*"[^"]*"%s*:%s*["\']?()',
  "^%s*%-?%s*'[^']*'%s*:%s*[\"']?()",
  -- Dockerfile ENV/ARG KEY=value and ENV KEY value
  '^%s*[Ee][Nn][Vv]%s+[%w_]+[=%s]%s*["\']?()',
  '^%s*[Aa][Rr][Gg]%s+[%w_]+=%s*["\']?()',
  -- <element attr="x">value
  '^%s*<[%w_.:%-]+[^>/]*>%s*()',
}

---Byte column (0-indexed) where the value starts on a line, if it looks like
---one carries a value at all.
---@param line string
---@return number|nil
function M.value_start(line)
  for _, pattern in ipairs(VALUE_START_PATTERNS) do
    local pos = line:match(pattern)
    if pos and pos <= #line then
      return pos - 1
    end
  end
  return nil
end

---Drop what trails a value on the same line: spaces, a closing tag, a trailing
---comma and a closing quote.
---@param text string
---@return string
function M.trim_value(text)
  local value = text:gsub('%s+$', ''):gsub('</[%w_.:%-]+>$', ''):gsub(',$', '')
  value = value:gsub('["\']$', '')
  return value
end

---The value on a line, with the column it starts at.
---@param line string
---@return number|nil col 0-indexed byte column
---@return string|nil value
function M.find_value(line)
  local col = M.value_start(line)
  if not col or col >= #line then
    return nil, nil
  end
  local value = M.trim_value(line:sub(col + 1))
  if value == '' then
    return nil, nil
  end
  return col, value
end

---The same line with its value replaced by a mask of the same display width.
---Returns nil when the line doesn't look like it carries a value.
---@param line string
---@param cfg table Config table (global or buffer-local)
---@return string|nil
function M.mask_line(line, cfg)
  local col, value = M.find_value(line)
  if not col then
    return nil
  end
  local mask = styles.generate_hidden_text(cfg.style, vim.fn.strdisplaywidth(value), value, cfg)
  return line:sub(1, col) .. mask .. line:sub(col + #value + 1)
end

return M
