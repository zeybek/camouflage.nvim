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

  -- Use curl with timeout and silent mode
  -- -s: silent, -f: fail silently on HTTP errors, --max-time: timeout
  vim.system({ 'curl', '-s', '-f', '--max-time', '10', url }, { text = true }, function(obj)
    if obj.code ~= 0 or not obj.stdout then
      -- Fail silently on network errors
      wrapped_callback(nil, nil)
      return
    end

    ---@type PwnedSuffixes
    local suffixes = {}

    -- Parse response: each line is "SUFFIX:COUNT"
    for line in obj.stdout:gmatch('[^\r\n]+') do
      local suffix, count_str = line:match('^(%x+):(%d+)$')
      if suffix and count_str then
        suffixes[suffix:upper()] = tonumber(count_str) or 0
      end
    end

    wrapped_callback(nil, suffixes)
  end)
end

return M
