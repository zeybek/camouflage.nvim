---@mod camouflage.styles Masking styles

local M = {}

local config = require('camouflage.config')

M.STYLES = {
  TEXT = 'text',
  DOTTED = 'dotted',
  STARS = 'stars',
  SCRAMBLE = 'scramble',
}

---Generate masked text based on style and configuration
---@param style string The masking style to use
---@param length number The length of the original text
---@param original_text string|nil The original text (used for scramble style)
---@param cfg table|nil Optional config table (for buffer-local overrides)
---@return string The masked text
function M.generate_hidden_text(style, length, original_text, cfg)
  -- Use provided config or fall back to global config
  cfg = cfg or config.get()
  local target_length = cfg.mask_length or length

  if style == M.STYLES.TEXT then
    return cfg.hidden_text
  elseif style == M.STYLES.DOTTED then
    return string.rep('•', target_length)
  elseif style == M.STYLES.STARS then
    return string.rep(cfg.mask_char, target_length)
  elseif style == M.STYLES.SCRAMBLE then
    if original_text and #original_text > 2 then
      return M.scramble_text(original_text)
    end
    return string.rep('*', target_length)
  end

  return string.rep('*', target_length)
end

---@param text string
---@return string
function M.scramble_text(text)
  if #text <= 2 then
    return string.rep('*', #text)
  end

  -- Deterministic seed based on text content
  local seed = 0
  for i = 1, #text do
    seed = seed + text:byte(i) * i
  end
  math.randomseed(seed)

  local chars = {}
  for i = 1, #text do
    chars[i] = text:sub(i, i)
  end
  for i = #chars, 2, -1 do
    local j = math.random(i)
    chars[i], chars[j] = chars[j], chars[i]
  end

  if #text > 3 then
    local first_char = text:sub(1, 1)
    if chars[1] ~= first_char then
      for k = 2, #chars do
        if chars[k] == first_char then
          chars[1], chars[k] = chars[k], chars[1]
          break
        end
      end
    end

    local last_char = text:sub(-1)
    if chars[#chars] ~= last_char then
      for k = 1, #chars - 1 do
        if chars[k] == last_char then
          chars[#chars], chars[k] = chars[k], chars[#chars]
          break
        end
      end
    end
  end

  return table.concat(chars)
end

---@param style string
---@return boolean
function M.is_valid_style(style)
  return style == M.STYLES.TEXT
    or style == M.STYLES.DOTTED
    or style == M.STYLES.STARS
    or style == M.STYLES.SCRAMBLE
end

---@return string[]
function M.get_available_styles()
  return { M.STYLES.TEXT, M.STYLES.DOTTED, M.STYLES.STARS, M.STYLES.SCRAMBLE }
end

return M
