-- Plugin managers clone with --recurse-submodules, and lazy.nvim marks every
-- submodule active. One that appears in a later commit was never cloned, so an
-- existing install fails to update with "could not reset submodule index"
-- (#141). The repository ships no submodules.
describe('repository', function()
  it('has no submodules', function()
    local entries = vim.fn.systemlist({ 'git', 'ls-files', '--stage' })
    assert.equals(0, vim.v.shell_error, table.concat(entries, '\n'))

    local gitlinks = vim.tbl_filter(function(line)
      return line:match('^160000 ') ~= nil
    end, entries)

    assert.same({}, gitlinks)
    assert.equals(0, vim.fn.filereadable('.gitmodules'))
  end)
end)
