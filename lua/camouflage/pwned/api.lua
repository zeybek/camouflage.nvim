---@mod camouflage.pwned.api HIBP Pwned Passwords API client
---@brief [[
--- Client for the Have I Been Pwned Passwords API.
--- Uses k-anonymity: only sends first 5 chars of SHA-1 hash.
--- See: https://haveibeenpwned.com/API/v3#PwnedPasswords
---@brief ]]

local M = {}

local API_URL = 'https://api.pwnedpasswords.com/range/'

---Check if curl is available
---@return boolean
function M.is_available()
  return vim.fn.executable('curl') == 1
end

---@alias PwnedSuffixes table<string, number> Map of hash suffix to breach count

---Parse a HIBP range response into a suffix->count map.
---Each line is "SUFFIX:COUNT". Padding entries (added by the Add-Padding
---header) always have COUNT 0 and MUST be discarded — keeping them would let a
---consumer report a false breach for a zero-count suffix.
---@param body string Raw response body
---@return PwnedSuffixes
function M.parse_response(body)
  ---@type PwnedSuffixes
  local suffixes = {}
  for line in body:gmatch('[^\r\n]+') do
    local suffix, count_str = line:match('^(%x+):(%d+)$')
    if suffix and count_str then
      local count = tonumber(count_str) or 0
      if count > 0 then
        suffixes[suffix:upper()] = count
      end
    end
  end
  return suffixes
end

---Fetch hash suffixes for a prefix from HIBP API
---@param prefix string First 5 chars of SHA-1 hash (e.g., "5BAA6")
---@param callback fun(err: string|nil, suffixes: PwnedSuffixes|nil) Called with results
function M.check_prefix(prefix, callback)
  local wrapped_callback = vim.schedule_wrap(callback)

  if not M.is_available() then
    wrapped_callback('curl not available', nil)
    return
  end

  if not prefix or #prefix ~= 5 then
    wrapped_callback('invalid prefix', nil)
    return
  end

  local url = API_URL .. prefix:upper()

  -- -s silent, -f fail on HTTP errors, --max-time timeout.
  -- Add-Padding pads the response to a random 800-1000 entries so a passive
  -- network observer cannot infer which prefix bucket was queried; HIBP
  -- requires a User-Agent or returns HTTP 403.
  local cmd = {
    'curl',
    '-s',
    '-f',
    '--max-time',
    '10',
    '-H',
    'Add-Padding: true',
    '-A',
    'camouflage.nvim',
    url,
  }
  vim.system(cmd, { text = true }, function(obj)
    if obj.code ~= 0 or not obj.stdout then
      -- Surface the failure (vs. "not pwned") so callers can distinguish it.
      wrapped_callback('curl request failed (exit ' .. tostring(obj.code) .. ')', nil)
      return
    end

    wrapped_callback(nil, M.parse_response(obj.stdout))
  end)
end

return M
