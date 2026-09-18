---@mod camouflage.styles Masking styles

local M = {}

local config = require('camouflage.config')

M.STYLES = {
  TEXT = 'text',
  DOTTED = 'dotted',
  STARS = 'stars',
  SCRAMBLE = 'scramble',
  PARTIAL = 'partial',
}

---Keep the first and last few characters of a value and cover the rest, the way
---a dashboard shows a key id. Leaks what it is asked to leak, so it is only
---reachable per key through a policy rule.
---@param text string
---@param cfg table show_start / show_end, both optional
---@return string
function M.partial_text(text, cfg)
  local chars = vim.fn.strchars(text)
  local show_start = math.max(0, math.floor(tonumber(cfg.show_start) or 0))
  local show_end = math.max(0, math.floor(tonumber(cfg.show_end) or 0))
  local mask_char = cfg.mask_char or '*'

  -- Never reveal the whole value: if the visible ends would meet, fall back to
  -- covering everything.
  if show_start + show_end >= chars then
    return string.rep(mask_char, chars)
  end

  local head = show_start > 0 and vim.fn.strcharpart(text, 0, show_start) or ''
  local tail = show_end > 0 and vim.fn.strcharpart(text, chars - show_end, show_end) or ''
  return head .. string.rep(mask_char, chars - show_start - show_end) .. tail
end

---Generate masked text based on style and configuration.
---
---`width` is the DISPLAY-CELL width of the value being covered (callers pass
---vim.fn.strdisplaywidth(value)). The result is always padded with trailing
---spaces to at least that width, because an overlay virt_text is not clipped at
---the extmark's end_col: a mask narrower than the value would leave the value's
---tail visible. Over-wide masks (e.g. a long 'text' style) are left as-is —
---they conceal adjacent cells rather than reveal the secret.
---@param style string The masking style to use
---@param width number Display-cell width of the original value
---@param original_text string|nil The original text (used for scramble style)
---@param cfg table|nil Optional config table (for buffer-local overrides)
---@return string The masked text
function M.generate_hidden_text(style, width, original_text, cfg)
  -- Use provided config or fall back to global config
  cfg = cfg or config.get()
  local target_length = cfg.mask_length or width

  local masked
  if style == M.STYLES.TEXT then
    masked = cfg.hidden_text
  elseif style == M.STYLES.DOTTED then
    masked = string.rep('•', target_length)
  elseif style == M.STYLES.STARS then
    masked = string.rep(cfg.mask_char, target_length)
  elseif style == M.STYLES.PARTIAL then
    masked = original_text and M.partial_text(original_text, cfg)
      or string.rep(cfg.mask_char, target_length)
  elseif style == M.STYLES.SCRAMBLE then
    if original_text and vim.fn.strchars(original_text) > 2 then
      masked = M.scramble_text(original_text)
    else
      masked = string.rep('*', target_length)
    end
  else
    masked = string.rep('*', target_length)
  end

  -- Pad to fully cover the value's display width (never truncate).
  local mask_width = vim.fn.strdisplaywidth(masked)
  if mask_width < width then
    masked = masked .. string.rep(' ', width - mask_width)
  end
  return masked
end

---Build a deterministic, self-contained PRNG seeded from the text. Uses the
---Park-Miller minimal-standard LCG so it never touches the editor-global RNG
---(math.randomseed) and needs no bit operations.
---@param text string
---@return fun(n: number): number
local function make_rng(text)
  local seed = 0
  for i = 1, #text do
    seed = (seed + text:byte(i) * i) % 2147483646
  end
  seed = seed + 1 -- avoid the 0 fixed point
  return function(n)
    seed = (seed * 16807) % 2147483647
    return (seed % n) + 1
  end
end

---@param text string
---@return string
function M.scramble_text(text)
  -- Split on every character so multibyte (UTF-8) values shuffle whole
  -- characters instead of bytes (which would produce invalid UTF-8 / mojibake).
  local orig = vim.fn.split(text, '\\zs')
  local n = #orig
  if n <= 2 then
    return string.rep('*', n)
  end

  local chars = {}
  for i = 1, n do
    chars[i] = orig[i]
  end

  local rand = make_rng(text)
  for i = n, 2, -1 do
    local j = rand(i)
    chars[i], chars[j] = chars[j], chars[i]
  end

  if n > 3 then
    local first_char = orig[1]
    if chars[1] ~= first_char then
      for k = 2, n do
        if chars[k] == first_char then
          chars[1], chars[k] = chars[k], chars[1]
          break
        end
      end
    end

    local last_char = orig[n]
    if chars[n] ~= last_char then
      for k = 1, n - 1 do
        if chars[k] == last_char then
          chars[n], chars[k] = chars[k], chars[n]
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
