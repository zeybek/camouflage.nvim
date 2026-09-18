-- Results are anchored to their line so they move with the text. The anchor
-- walk is what keeps them in place, and it must not run once per stored result:
-- that made a pass over n results cost n^2 extmark lookups.
local store = require('camouflage.checks.store')

describe('camouflage.checks.store anchors', function()
  local bufnr
  local original_get_extmark = vim.api.nvim_buf_get_extmark_by_id
  local lookups = 0

  local function result(text)
    return { severity = 'info', text = text }
  end

  local function fill(lines)
    local content = {}
    for i = 1, lines do
      content[i] = ('KEY_%03d=value'):format(i)
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  end

  before_each(function()
    store._reset()
    bufnr = vim.api.nvim_create_buf(true, false)
    lookups = 0
    vim.api.nvim_buf_get_extmark_by_id = function(...)
      lookups = lookups + 1
      return original_get_extmark(...)
    end
  end)

  after_each(function()
    vim.api.nvim_buf_get_extmark_by_id = original_get_extmark
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('does not walk every anchor again for each stored result', function()
    local lines = 200
    fill(lines)

    for lnum = 0, lines - 1 do
      store.set(bufnr, lnum, 'probe', result('x'))
    end

    assert.equals(lines, #store.lines_with_results(bufnr))
    -- One walk covers the whole pass. Anything proportional to lines^2 means
    -- the walk moved back into the per-result path.
    assert.is_true(
      lookups <= lines * 2,
      ('anchor lookups grew with the number of results: %d for %d lines'):format(lookups, lines)
    )
  end)

  it('moves results to where their line went', function()
    fill(3)
    store.set(bufnr, 0, 'probe', result('first'))
    store.set(bufnr, 2, 'probe', result('third'))

    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '# one', '# two' })

    assert.same({ 2, 4 }, store.lines_with_results(bufnr))
    assert.equals('first', store.get(bufnr, 2, 'probe').text)
    assert.equals('third', store.get(bufnr, 4, 'probe').text)
  end)

  it('keeps following the text after later edits', function()
    fill(3)
    store.set(bufnr, 1, 'probe', result('second'))

    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '# one' })
    assert.same({ 2 }, store.lines_with_results(bufnr))

    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '# two' })
    assert.same({ 3 }, store.lines_with_results(bufnr))

    vim.api.nvim_buf_set_lines(bufnr, 0, 2, false, {})
    assert.same({ 1 }, store.lines_with_results(bufnr))
  end)

  it('still syncs after the buffer was cleared and refilled', function()
    fill(3)
    store.set(bufnr, 0, 'probe', result('first'))
    store.clear_buffer(bufnr)
    assert.same({}, store.lines_with_results(bufnr))

    store.set(bufnr, 0, 'probe', result('again'))
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '# one' })

    assert.same({ 1 }, store.lines_with_results(bufnr))
  end)
end)
