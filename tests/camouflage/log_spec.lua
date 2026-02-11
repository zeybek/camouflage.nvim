---@diagnostic disable: undefined-field
local log = require('camouflage.log')
local config = require('camouflage.config')

describe('camouflage.log', function()
  local original_notify
  local notify_calls

  before_each(function()
    -- Reset config
    config.setup({ debug = false })

    -- Mock vim.notify to capture calls
    original_notify = vim.notify
    notify_calls = {}
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = original_notify
  end)

  describe('levels', function()
    it('should have TRACE level', function()
      assert.equals(vim.log.levels.TRACE, log.levels.TRACE)
    end)

    it('should have DEBUG level', function()
      assert.equals(vim.log.levels.DEBUG, log.levels.DEBUG)
    end)

    it('should have INFO level', function()
      assert.equals(vim.log.levels.INFO, log.levels.INFO)
    end)

    it('should have WARN level', function()
      assert.equals(vim.log.levels.WARN, log.levels.WARN)
    end)

    it('should have ERROR level', function()
      assert.equals(vim.log.levels.ERROR, log.levels.ERROR)
    end)
  end)

  describe('debug mode disabled', function()
    before_each(function()
      config.setup({ debug = false })
    end)

    it('should not log TRACE when debug=false', function()
      log.trace('test message')
      assert.equals(0, #notify_calls)
    end)

    it('should not log DEBUG when debug=false', function()
      log.debug('test message')
      assert.equals(0, #notify_calls)
    end)

    it('should not log INFO when debug=false', function()
      log.info('test message')
      assert.equals(0, #notify_calls)
    end)

    it('should log WARN when debug=false', function()
      log.warn('warning message')
      assert.equals(1, #notify_calls)
      assert.equals(vim.log.levels.WARN, notify_calls[1].level)
      assert.is_true(notify_calls[1].msg:find('warning message') ~= nil)
    end)

    it('should log ERROR when debug=false', function()
      log.error('error message')
      assert.equals(1, #notify_calls)
      assert.equals(vim.log.levels.ERROR, notify_calls[1].level)
      assert.is_true(notify_calls[1].msg:find('error message') ~= nil)
    end)
  end)

  describe('debug mode enabled', function()
    before_each(function()
      config.setup({ debug = true })
    end)

    it('should log TRACE when debug=true', function()
      log.trace('trace message')
      assert.equals(1, #notify_calls)
      assert.equals(vim.log.levels.TRACE, notify_calls[1].level)
      assert.is_true(notify_calls[1].msg:find('trace message') ~= nil)
    end)

    it('should log DEBUG when debug=true', function()
      log.debug('debug message')
      assert.equals(1, #notify_calls)
      assert.equals(vim.log.levels.DEBUG, notify_calls[1].level)
      assert.is_true(notify_calls[1].msg:find('debug message') ~= nil)
    end)

    it('should log INFO when debug=true', function()
      log.info('info message')
      assert.equals(1, #notify_calls)
      assert.equals(vim.log.levels.INFO, notify_calls[1].level)
      assert.is_true(notify_calls[1].msg:find('info message') ~= nil)
    end)

    it('should log WARN when debug=true', function()
      log.warn('warning message')
      assert.equals(1, #notify_calls)
      assert.equals(vim.log.levels.WARN, notify_calls[1].level)
    end)

    it('should log ERROR when debug=true', function()
      log.error('error message')
      assert.equals(1, #notify_calls)
      assert.equals(vim.log.levels.ERROR, notify_calls[1].level)
    end)
  end)

  describe('message formatting', function()
    before_each(function()
      config.setup({ debug = true })
    end)

    it('should format messages with string arguments', function()
      log.debug('Hello %s', 'world')
      assert.equals(1, #notify_calls)
      assert.is_true(notify_calls[1].msg:find('Hello world') ~= nil)
    end)

    it('should format messages with number arguments', function()
      log.debug('Value is %d', 42)
      assert.equals(1, #notify_calls)
      assert.is_true(notify_calls[1].msg:find('Value is 42') ~= nil)
    end)

    it('should format messages with multiple arguments', function()
      log.debug('Buffer %d, line %d', 1, 10)
      assert.equals(1, #notify_calls)
      assert.is_true(notify_calls[1].msg:find('Buffer 1, line 10') ~= nil)
    end)

    it('should handle nil arguments', function()
      log.debug('Value is %s', nil)
      assert.equals(1, #notify_calls)
      assert.is_true(notify_calls[1].msg:find('nil') ~= nil)
    end)

    it('should handle table arguments', function()
      log.debug('Data: %s', { key = 'value' })
      assert.equals(1, #notify_calls)
      assert.is_true(notify_calls[1].msg:find('key') ~= nil)
    end)

    it('should include level prefix', function()
      log.debug('test')
      assert.is_true(notify_calls[1].msg:find('%[camouflage:DEBUG%]') ~= nil)
    end)
  end)

  describe('inspect', function()
    before_each(function()
      config.setup({ debug = true })
    end)

    it('should inspect tables with label', function()
      log.inspect('config', { enabled = true })
      assert.equals(1, #notify_calls)
      assert.is_true(notify_calls[1].msg:find('config') ~= nil)
      assert.is_true(notify_calls[1].msg:find('enabled') ~= nil)
    end)

    it('should not inspect when debug=false', function()
      config.setup({ debug = false })
      log.inspect('config', { enabled = true })
      assert.equals(0, #notify_calls)
    end)
  end)

  describe('pcall_error', function()
    before_each(function()
      config.setup({ debug = true })
    end)

    it('should log pcall error with operation name', function()
      log.pcall_error('nvim_buf_get_lines', 'Invalid buffer')
      assert.equals(1, #notify_calls)
      assert.is_true(notify_calls[1].msg:find('nvim_buf_get_lines failed') ~= nil)
      assert.is_true(notify_calls[1].msg:find('Invalid buffer') ~= nil)
    end)

    it('should log pcall error with context', function()
      log.pcall_error('nvim_buf_set_extmark', 'Out of range', { bufnr = 1, row = 5 })
      assert.equals(1, #notify_calls)
      assert.is_true(notify_calls[1].msg:find('bufnr=1') ~= nil)
      assert.is_true(notify_calls[1].msg:find('row=5') ~= nil)
    end)

    it('should not log when debug=false', function()
      config.setup({ debug = false })
      log.pcall_error('nvim_buf_get_lines', 'error')
      assert.equals(0, #notify_calls)
    end)
  end)
end)
