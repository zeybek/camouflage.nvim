-- Checks ask the same questions about the same values on every pass. The memo
-- keeps the answers per buffer, so the work happens once per value.
local memo = require('camouflage.checks.memo')

describe('camouflage.checks.memo', function()
  local bufnr

  before_each(function()
    memo.clear_all()
    bufnr = vim.api.nvim_create_buf(true, false)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('computes once and answers from then on', function()
    local calls = 0
    local function compute()
      calls = calls + 1
      return 'answer'
    end

    assert.equals('answer', memo.get(bufnr, 1, 'key', compute))
    assert.equals('answer', memo.get(bufnr, 1, 'key', compute))
    assert.equals(1, calls)
  end)

  it('remembers that there was nothing to report', function()
    local calls = 0
    local function compute()
      calls = calls + 1
      return nil
    end

    assert.is_nil(memo.get(bufnr, 1, 'key', compute))
    assert.is_nil(memo.get(bufnr, 1, 'key', compute))
    assert.equals(1, calls)
  end)

  it('starts over when the config generation moves', function()
    local calls = 0
    local function compute()
      calls = calls + 1
      return calls
    end

    assert.equals(1, memo.get(bufnr, 1, 'key', compute))
    assert.equals(2, memo.get(bufnr, 2, 'key', compute))
    assert.equals(2, memo.get(bufnr, 2, 'key', compute))
    assert.equals(2, calls)
  end)

  it('keeps buffers apart', function()
    local other = vim.api.nvim_create_buf(true, false)
    memo.get(bufnr, 1, 'key', function()
      return 'first'
    end)

    assert.equals(
      'second',
      memo.get(other, 1, 'key', function()
        return 'second'
      end)
    )
    vim.api.nvim_buf_delete(other, { force = true })
  end)

  it('forgets a buffer on clear', function()
    local calls = 0
    local function compute()
      calls = calls + 1
      return 'answer'
    end

    memo.get(bufnr, 1, 'key', compute)
    memo.clear(bufnr)
    memo.get(bufnr, 1, 'key', compute)

    assert.equals(2, calls)
    assert.equals(1, memo.count(bufnr))
  end)

  it('drops everything rather than growing without a limit', function()
    for i = 1, 5000 do
      memo.get(bufnr, 1, 'key' .. i, function()
        return i
      end)
    end

    assert.is_true(memo.count(bufnr) < 5000)
  end)
end)
