local expiry = require('camouflage.checks.expiry')
local checks = require('camouflage.checks')
local store = require('camouflage.checks.store')
local config = require('camouflage.config')

-- Pure-Lua base64 encoder (vim.base64.encode is Neovim 0.10+).
local ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64_encode(input)
  local out, i = {}, 1
  while i <= #input do
    local b1 = string.byte(input, i) or 0
    local b2 = string.byte(input, i + 1)
    local b3 = string.byte(input, i + 2)
    local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
    table.insert(out, ALPHA:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1))
    table.insert(out, ALPHA:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1))
    table.insert(
      out,
      b2 and ALPHA:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or '='
    )
    table.insert(out, b3 and ALPHA:sub(n % 64 + 1, n % 64 + 1) or '=')
    i = i + 3
  end
  return table.concat(out)
end

local function encode_segment(tbl)
  local json = vim.json.encode(tbl)
  local b64 = b64_encode(json)
  return (b64:gsub('+', '-'):gsub('/', '_'):gsub('=', ''))
end

local function make_jwt(claims, header)
  return table.concat({
    encode_segment(header or { alg = 'RS256', typ = 'JWT' }),
    encode_segment(claims or {}),
    'sig',
  }, '.')
end

local function fresh_buffer()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'TOKEN=...' })
  return bufnr
end

describe('camouflage.checks.expiry', function()
  before_each(function()
    config.setup()
    store._reset()
    expiry.setup()
  end)

  after_each(function()
    expiry.teardown()
  end)

  describe('refresh_buffer (classification)', function()
    it('does not show a badge for tokens far beyond show_threshold', function()
      local bufnr = fresh_buffer()
      -- Seed an existing result with exp very far in the future
      checks.set_result(bufnr, 0, 'expiry', {
        severity = 'info',
        text = 'placeholder',
        data = { exp = os.time() + 86400 * 365, iss = nil },
      })
      expiry.refresh_buffer(bufnr)
      assert.is_nil(store.get(bufnr, 0, 'expiry'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('produces a warning badge when within warn_threshold', function()
      local bufnr = fresh_buffer()
      checks.set_result(bufnr, 0, 'expiry', {
        severity = 'info',
        text = 'placeholder',
        data = { exp = os.time() + 600, iss = nil }, -- 10 minutes
      })
      expiry.refresh_buffer(bufnr)
      local r = store.get(bufnr, 0, 'expiry')
      assert.is_table(r)
      assert.equals('warning', r.severity)
      assert.is_not_nil(r.text:match('expires in'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('produces an expired badge when remaining <= 0', function()
      local bufnr = fresh_buffer()
      checks.set_result(bufnr, 0, 'expiry', {
        severity = 'info',
        text = 'placeholder',
        data = { exp = os.time() - 3600, iss = nil },
      })
      expiry.refresh_buffer(bufnr)
      local r = store.get(bufnr, 0, 'expiry')
      assert.is_table(r)
      assert.equals('error', r.severity)
      assert.is_not_nil(r.text:match('expired'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('produces a valid badge between warn and show thresholds', function()
      local bufnr = fresh_buffer()
      checks.set_result(bufnr, 0, 'expiry', {
        severity = 'info',
        text = 'placeholder',
        data = { exp = os.time() + 7200, iss = nil }, -- 2 hours
      })
      expiry.refresh_buffer(bufnr)
      local r = store.get(bufnr, 0, 'expiry')
      assert.is_table(r)
      assert.equals('info', r.severity)
      assert.is_not_nil(r.text:match('valid'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('includes provider name when iss is recognized', function()
      local bufnr = fresh_buffer()
      checks.set_result(bufnr, 0, 'expiry', {
        severity = 'info',
        text = 'placeholder',
        data = { exp = os.time() + 600, iss = 'https://accounts.google.com' },
      })
      expiry.refresh_buffer(bufnr)
      local r = store.get(bufnr, 0, 'expiry')
      assert.is_not_nil(r.text:match('Google'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('variable_detected hook integration', function()
    it('adds a badge for a parsed JWT variable', function()
      local bufnr = fresh_buffer()
      local hooks = require('camouflage.hooks')
      local token = make_jwt({ exp = os.time() + 600 })
      hooks.emit('before_decorate', bufnr, 'foo.env')
      hooks.emit('variable_detected', bufnr, {
        key = 'TOKEN',
        value = token,
        line_number = 0,
        start_index = 0,
        end_index = #token,
        is_nested = false,
        is_commented = false,
      })
      local r = store.get(bufnr, 0, 'expiry')
      assert.is_table(r)
      assert.equals('warning', r.severity)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does not add a badge for non-JWT values', function()
      local bufnr = fresh_buffer()
      local hooks = require('camouflage.hooks')
      hooks.emit('variable_detected', bufnr, {
        key = 'PASSWORD',
        value = 'hunter2',
        line_number = 0,
        start_index = 0,
        end_index = 7,
        is_nested = false,
        is_commented = false,
      })
      assert.is_nil(store.get(bufnr, 0, 'expiry'))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('is_enabled', function()
    it('respects the config flag', function()
      config.setup({ checks = { expiry = { enabled = false } } })
      assert.is_false(expiry.is_enabled())
      config.setup({ checks = { expiry = { enabled = true } } })
      assert.is_true(expiry.is_enabled())
    end)
  end)
end)
