---@mod camouflage.pwned.check Pwned password check orchestrator
---@brief [[
--- Orchestrates the password breach checking process.
--- Combines hashing, caching, API calls, and UI updates.
---@brief ]]

local M = {}

local hash_mod = require('camouflage.pwned.hash')
local cache = require('camouflage.pwned.cache')
local api = require('camouflage.pwned.api')
local ui = require('camouflage.pwned.ui')

---@class PwnedCheckResult
---@field pwned boolean Whether the password was found in breaches
---@field count number Number of times found (0 if not pwned)

---Check a single value against HIBP
---@param value string The password/secret value to check
---@param callback fun(result: PwnedCheckResult|nil) Called with result or nil on error
function M.check_value(value, callback)
  -- Step 1: Calculate SHA-1 hash
  hash_mod.sha1(value, function(hash_result)
    if not hash_result then
      callback(nil)
      return
    end

    -- Step 2: Check cache first
    local cached = cache.get(hash_result.hash)
    if cached then
      callback(cached)
      return
    end

    -- Step 3: Call API with prefix
    api.check_prefix(hash_result.prefix, function(err, suffixes)
      if err or not suffixes then
        -- Fail silently - don't cache failures
        callback(nil)
        return
      end

      -- Step 4: Search for our suffix in response
      local count = suffixes[hash_result.suffix] or 0
      local result = {
        pwned = count > 0,
        count = count,
      }

      -- Step 5: Cache result
      cache.set(hash_result.hash, result)

      -- Step 6: Call callback
      callback(result)
    end)
  end)
end

---@class ParsedVariable
---@field name string Variable name
---@field value string Variable value
---@field line number 0-indexed line number
---@field start_col number Start column
---@field end_col number End column

---Check a single variable and update UI
---@param bufnr number Buffer number
---@param var ParsedVariable Variable to check
---@param config PwnedUIConfig|nil UI configuration
---@param callback fun(result: PwnedCheckResult|nil)|nil Optional callback
function M.check_variable(bufnr, var, config, callback)
  M.check_value(var.value, function(result)
    if result and result.pwned then
      ui.mark_pwned(bufnr, var.line, result.count, config)
    end
    if callback then
      callback(result)
    end
  end)
end

---Check all masked variables in a buffer
---Processes sequentially to avoid overwhelming API
---@param bufnr number Buffer number
---@param variables ParsedVariable[] Variables to check
---@param config PwnedUIConfig|nil UI configuration
---@param callback fun(results: table<string, PwnedCheckResult>)|nil Called when all checks complete
function M.check_buffer(bufnr, variables, config, callback)
  if not variables or #variables == 0 then
    if callback then
      callback({})
    end
    return
  end

  ---@type table<string, PwnedCheckResult>
  local results = {}
  local index = 1

  ---Process next variable in queue
  local function process_next()
    if index > #variables then
      -- All done
      if callback then
        callback(results)
      end
      return
    end

    local var = variables[index]
    index = index + 1

    M.check_variable(bufnr, var, config, function(result)
      if result then
        results[var.name] = result
      end
      -- Process next (sequential to avoid API rate limiting)
      process_next()
    end)
  end

  -- Start processing
  process_next()
end

---Check if the feature is available (all dependencies met)
---@return boolean
function M.is_available()
  return hash_mod.is_available() and api.is_available()
end

return M
