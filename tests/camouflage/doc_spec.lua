-- Plugin managers run :helptags on install, and one duplicate tag fails the
-- whole file with E154.
describe('doc/camouflage.txt', function()
  it('generates help tags without errors', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile(vim.fn.readfile('doc/camouflage.txt'), dir .. '/camouflage.txt')

    local ok, err = pcall(vim.cmd, 'helptags ' .. vim.fn.fnameescape(dir))

    vim.fn.delete(dir, 'rf')
    assert.is_true(ok, tostring(err))
  end)
end)
