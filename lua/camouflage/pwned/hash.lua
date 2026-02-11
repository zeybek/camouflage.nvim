---@mod camouflage.pwned.hash SHA-1 hash utilities
---@brief [[
--- Provides SHA-1 hashing using CLI tools (sha1sum or openssl fallback).
--- Used by the HIBP integration to hash passwords before checking.
---@brief ]]

local M = {}

---Check if sha1sum is available
---@return boolean
function M.has_sha1sum()
  return vim.fn.executable('sha1sum') == 1
end

---Check if openssl is available
---@return boolean
function M.has_openssl()
  return vim.fn.executable('openssl') == 1
end

---Check if any SHA-1 tool is available
---@return boolean
function M.is_available()
  return M.has_sha1sum() or M.has_openssl()
end

---@class Sha1Result
---@field hash string Full 40-char uppercase SHA-1 hash
---@field prefix string First 5 characters of hash
---@field suffix string Remaining 35 characters of hash

---Calculate SHA-1 hash asynchronously
---@param value string The value to hash
---@param callback fun(result: Sha1Result|nil) Called with result or nil on error
function M.sha1(value, callback)
  local wrapped_callback = vim.schedule_wrap(callback)

  if not M.is_available() then
    wrapped_callback(nil)
    return
  end

  ---@param hash_output string Raw output from hash command
  ---@return Sha1Result|nil
  local function parse_hash(hash_output)
    if not hash_output then
      return nil
    end

    -- Extract just the hash (remove any extra output)
    local hash = hash_output:match('%x+')
    if not hash or #hash ~= 40 then
      return nil
    end

    hash = hash:upper()
    return {
      hash = hash,
      prefix = hash:sub(1, 5),
      suffix = hash:sub(6),
    }
  end

  -- Escape value for shell - use printf which handles special chars better
  -- We use base64 encoding to safely pass the value through shell
  local base64_value = vim.base64.encode(value)

  if M.has_sha1sum() then
    -- Use base64 decode piped to sha1sum for safety
    local cmd = string.format(
      "echo %s | base64 -d | sha1sum | cut -d' ' -f1",
      vim.fn.shellescape(base64_value)
    )
    vim.system({ 'sh', '-c', cmd }, { text = true }, function(obj)
      if obj.code == 0 and obj.stdout then
        local result = parse_hash(obj.stdout)
        wrapped_callback(result)
      else
        wrapped_callback(nil)
      end
    end)
  elseif M.has_openssl() then
    -- Fallback to openssl
    local cmd = string.format(
      "echo %s | base64 -d | openssl sha1 | awk '{print $NF}'",
      vim.fn.shellescape(base64_value)
    )
    vim.system({ 'sh', '-c', cmd }, { text = true }, function(obj)
      if obj.code == 0 and obj.stdout then
        local result = parse_hash(obj.stdout)
        wrapped_callback(result)
      else
        wrapped_callback(nil)
      end
    end)
  else
    wrapped_callback(nil)
  end
end

return M
