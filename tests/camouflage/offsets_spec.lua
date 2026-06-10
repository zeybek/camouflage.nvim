local offsets = require('camouflage.offsets')

describe('camouflage.offsets', function()
  it('from_content gives 0-based byte offsets of each line start', function()
    local o = offsets.from_content('ab\ncde')
    assert.equals(0, o[1])
    assert.equals(3, o[2]) -- after 'ab\n'
  end)

  it('from_lines and from_content agree (including blank lines)', function()
    local content = 'API_KEY=secret\nDB=2\n\nLAST=x'
    local lines = vim.split(content, '\n', { plain = true })
    local a = offsets.from_lines(lines)
    local b = offsets.from_content(content)
    for i = 1, #lines do
      assert.equals(a[i], b[i], 'mismatch at line ' .. i)
    end
  end)
end)
