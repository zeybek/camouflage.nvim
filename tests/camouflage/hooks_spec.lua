local hooks = require('camouflage.hooks')

describe('camouflage.hooks', function()
  before_each(function()
    hooks.clear()
    hooks.setup(nil)
  end)

  describe('EVENTS', function()
    it('should have BEFORE_DECORATE event', function()
      assert.equals('before_decorate', hooks.EVENTS.BEFORE_DECORATE)
    end)

    it('should have VARIABLE_DETECTED event', function()
      assert.equals('variable_detected', hooks.EVENTS.VARIABLE_DETECTED)
    end)

    it('should have AFTER_DECORATE event', function()
      assert.equals('after_decorate', hooks.EVENTS.AFTER_DECORATE)
    end)
  end)

  describe('on', function()
    it('should register a listener and return an id', function()
      local id = hooks.on('before_decorate', function() end)
      assert.is_number(id)
      assert.is_true(id > 0)
    end)

    it('should return unique ids for each listener', function()
      local id1 = hooks.on('before_decorate', function() end)
      local id2 = hooks.on('before_decorate', function() end)
      assert.is_not.equals(id1, id2)
    end)

    it('should add listener to the list', function()
      hooks.on('before_decorate', function() end)
      local listeners = hooks.list('before_decorate')
      assert.equals(1, #listeners)
    end)
  end)

  describe('once', function()
    it('should register a one-time listener', function()
      local call_count = 0
      hooks.once('before_decorate', function()
        call_count = call_count + 1
      end)

      hooks.emit('before_decorate', 1, 'test.env')
      hooks.emit('before_decorate', 1, 'test.env')

      assert.equals(1, call_count)
    end)

    it('should return an id', function()
      local id = hooks.once('before_decorate', function() end)
      assert.is_number(id)
    end)
  end)

  describe('off', function()
    it('should unregister a listener by id', function()
      local id = hooks.on('before_decorate', function() end)
      local result = hooks.off('before_decorate', id)
      assert.is_true(result)
      assert.equals(0, #hooks.list('before_decorate'))
    end)

    it('should return false for non-existent id', function()
      local result = hooks.off('before_decorate', 999)
      assert.is_false(result)
    end)

    it('should return false for non-existent event', function()
      local result = hooks.off('nonexistent', 1)
      assert.is_false(result)
    end)
  end)

  describe('list', function()
    it('should return empty table for no listeners', function()
      local listeners = hooks.list('before_decorate')
      assert.is_table(listeners)
      assert.equals(0, #listeners)
    end)

    it('should return all listeners for an event', function()
      hooks.on('before_decorate', function() end)
      hooks.on('before_decorate', function() end)
      local listeners = hooks.list('before_decorate')
      assert.equals(2, #listeners)
    end)
  end)

  describe('clear', function()
    it('should clear all listeners for a specific event', function()
      hooks.on('before_decorate', function() end)
      hooks.on('after_decorate', function() end)

      hooks.clear('before_decorate')

      assert.equals(0, #hooks.list('before_decorate'))
      assert.equals(1, #hooks.list('after_decorate'))
    end)

    it('should clear all listeners when no event specified', function()
      hooks.on('before_decorate', function() end)
      hooks.on('after_decorate', function() end)

      hooks.clear()

      assert.equals(0, #hooks.list('before_decorate'))
      assert.equals(0, #hooks.list('after_decorate'))
    end)
  end)

  describe('emit', function()
    it('should call registered listeners with arguments', function()
      local received_bufnr, received_filename
      hooks.on('before_decorate', function(bufnr, filename)
        received_bufnr = bufnr
        received_filename = filename
      end)

      hooks.emit('before_decorate', 42, 'test.env')

      assert.equals(42, received_bufnr)
      assert.equals('test.env', received_filename)
    end)

    it('should call multiple listeners', function()
      local call_count = 0
      hooks.on('before_decorate', function()
        call_count = call_count + 1
      end)
      hooks.on('before_decorate', function()
        call_count = call_count + 1
      end)

      hooks.emit('before_decorate', 1, 'test.env')

      assert.equals(2, call_count)
    end)

    it('should return false if any listener returns false', function()
      hooks.on('before_decorate', function()
        return true
      end)
      hooks.on('before_decorate', function()
        return false
      end)

      local result = hooks.emit('before_decorate', 1, 'test.env')
      assert.is_false(result)
    end)

    it('should return true if all listeners return true', function()
      hooks.on('before_decorate', function()
        return true
      end)
      hooks.on('before_decorate', function()
        return true
      end)

      local result = hooks.emit('before_decorate', 1, 'test.env')
      assert.is_true(result)
    end)

    it('should return nil if no listeners', function()
      local result = hooks.emit('before_decorate', 1, 'test.env')
      assert.is_nil(result)
    end)

    it('should handle listener errors gracefully', function()
      hooks.on('before_decorate', function()
        error('test error')
      end)

      -- Should not throw
      local result = hooks.emit('before_decorate', 1, 'test.env')
      assert.is_nil(result)
    end)
  end)

  describe('config hooks', function()
    it('should call config hook on emit', function()
      local called = false
      hooks.setup({
        on_before_decorate = function()
          called = true
        end,
      })

      hooks.emit('before_decorate', 1, 'test.env')
      assert.is_true(called)
    end)

    it('should call config hook before listeners', function()
      local order = {}

      hooks.setup({
        on_before_decorate = function()
          table.insert(order, 'config')
        end,
      })

      hooks.on('before_decorate', function()
        table.insert(order, 'listener')
      end)

      hooks.emit('before_decorate', 1, 'test.env')

      assert.equals('config', order[1])
      assert.equals('listener', order[2])
    end)

    it('should use config hook return value for filtering', function()
      hooks.setup({
        on_variable_detected = function()
          return false
        end,
      })

      local result = hooks.emit('variable_detected', 1, { key = 'test' })
      assert.is_false(result)
    end)
  end)

  describe('has_listeners', function()
    it('should return false when no listeners', function()
      assert.is_false(hooks.has_listeners('before_decorate'))
    end)

    it('should return true when listener registered', function()
      hooks.on('before_decorate', function() end)
      assert.is_true(hooks.has_listeners('before_decorate'))
    end)

    it('should return true when config hook set', function()
      hooks.setup({
        on_before_decorate = function() end,
      })
      assert.is_true(hooks.has_listeners('before_decorate'))
    end)
  end)
end)
