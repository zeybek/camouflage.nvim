local state = require('camouflage.state')

describe('camouflage.state', function()
  before_each(function()
    state.clear()
  end)

  describe('init_buffer', function()
    it('should create new buffer state', function()
      local bufnr = 1
      local buf_state = state.init_buffer(bufnr)

      assert.is_not_nil(buf_state)
      assert.is_true(buf_state.enabled)
      assert.is_table(buf_state.variables)
      assert.equals(0, #buf_state.variables)
      assert.is_nil(buf_state.parser)
    end)

    it('should return existing state if already initialized', function()
      local bufnr = 1
      local first = state.init_buffer(bufnr)
      first.enabled = false

      local second = state.init_buffer(bufnr)

      assert.is_false(second.enabled)
    end)

    it('should create separate state for different buffers', function()
      local state1 = state.init_buffer(1)
      local state2 = state.init_buffer(2)

      state1.enabled = false

      assert.is_false(state1.enabled)
      assert.is_true(state2.enabled)
    end)
  end)

  describe('get_buffer', function()
    it('should return nil for uninitialized buffer', function()
      local buf_state = state.get_buffer(999)

      assert.is_nil(buf_state)
    end)

    it('should return state for initialized buffer', function()
      state.init_buffer(1)
      local buf_state = state.get_buffer(1)

      assert.is_not_nil(buf_state)
      assert.is_true(buf_state.enabled)
    end)

    it('should use current buffer when bufnr is nil', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      state.init_buffer(bufnr)

      local buf_state = state.get_buffer(nil)

      assert.is_not_nil(buf_state)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('remove_buffer', function()
    it('should remove buffer state', function()
      state.init_buffer(1)
      assert.is_not_nil(state.get_buffer(1))

      state.remove_buffer(1)

      assert.is_nil(state.get_buffer(1))
    end)

    it('should not error when removing non-existent buffer', function()
      assert.has_no.errors(function()
        state.remove_buffer(999)
      end)
    end)
  end)

  describe('is_buffer_masked', function()
    it('should return false for uninitialized buffer', function()
      assert.is_false(state.is_buffer_masked(999))
    end)

    it('should return true for initialized enabled buffer', function()
      state.init_buffer(1)

      assert.is_true(state.is_buffer_masked(1))
    end)

    it('should return false for disabled buffer', function()
      state.init_buffer(1)
      state.update_buffer(1, { enabled = false })

      assert.is_false(state.is_buffer_masked(1))
    end)

    it('should use current buffer when bufnr is nil', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      state.init_buffer(bufnr)

      assert.is_true(state.is_buffer_masked(nil))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('set_variables', function()
    it('should store variables for buffer', function()
      local variables = {
        { key = 'API_KEY', value = 'secret' },
        { key = 'TOKEN', value = 'token123' },
      }

      state.set_variables(1, variables)
      local buf_state = state.get_buffer(1)

      assert.equals(2, #buf_state.variables)
      assert.equals('API_KEY', buf_state.variables[1].key)
      assert.equals('TOKEN', buf_state.variables[2].key)
    end)

    it('should initialize buffer if not exists', function()
      assert.is_nil(state.get_buffer(5))

      state.set_variables(5, { { key = 'TEST', value = 'value' } })

      assert.is_not_nil(state.get_buffer(5))
    end)

    it('should replace existing variables', function()
      state.set_variables(1, { { key = 'OLD', value = 'old' } })
      state.set_variables(1, { { key = 'NEW', value = 'new' } })

      local vars = state.get_variables(1)
      assert.equals(1, #vars)
      assert.equals('NEW', vars[1].key)
    end)
  end)

  describe('get_variables', function()
    it('should return empty table for uninitialized buffer', function()
      local vars = state.get_variables(999)

      assert.is_table(vars)
      assert.equals(0, #vars)
    end)

    it('should return variables for initialized buffer', function()
      state.set_variables(1, {
        { key = 'KEY1', value = 'val1' },
        { key = 'KEY2', value = 'val2' },
      })

      local vars = state.get_variables(1)

      assert.equals(2, #vars)
    end)

    it('should return empty table for buffer with no variables', function()
      state.init_buffer(1)

      local vars = state.get_variables(1)

      assert.is_table(vars)
      assert.equals(0, #vars)
    end)
  end)

  describe('clear', function()
    it('should remove all buffer states', function()
      state.init_buffer(1)
      state.init_buffer(2)
      state.init_buffer(3)

      state.clear()

      assert.is_nil(state.get_buffer(1))
      assert.is_nil(state.get_buffer(2))
      assert.is_nil(state.get_buffer(3))
    end)

    it('should work when no buffers exist', function()
      assert.has_no.errors(function()
        state.clear()
      end)
    end)
  end)

  describe('set_buffer', function()
    it('should set complete buffer state', function()
      local buf_state = {
        enabled = false,
        variables = { { key = 'TEST', value = 'val' } },
        parser = 'env',
      }

      state.set_buffer(1, buf_state)
      local result = state.get_buffer(1)

      assert.is_false(result.enabled)
      assert.equals('env', result.parser)
      assert.equals(1, #result.variables)
    end)
  end)

  describe('update_buffer', function()
    it('should update specific fields', function()
      state.init_buffer(1)
      state.update_buffer(1, { parser = 'json' })

      local buf_state = state.get_buffer(1)

      assert.is_true(buf_state.enabled)
      assert.equals('json', buf_state.parser)
    end)

    it('should initialize buffer if not exists', function()
      state.update_buffer(10, { enabled = false })

      local buf_state = state.get_buffer(10)

      assert.is_not_nil(buf_state)
      assert.is_false(buf_state.enabled)
    end)
  end)
end)
