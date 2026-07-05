-- Cross-parser contract test: every regex-fallback parser must emit
-- start_index/end_index as 0-based, end-exclusive byte offsets so the engine's
-- index_to_position math places masks correctly. This is the guard that would
-- have caught the netrc off-by-one (1-based emit) the audit found.
--
-- bufnr is intentionally nil so parsers that try TreeSitter first fall back to
-- their regex path (CI typically has no grammars installed anyway).

local contract = dofile(vim.fn.getcwd() .. '/tests/camouflage/helpers/contract.lua')

describe('camouflage parsers offset contract', function()
  before_each(function()
    require('camouflage.config').setup()
  end)

  local cases = {
    {
      name = 'env',
      parser = 'camouflage.parsers.env',
      content = 'API_KEY=secret123\nDB_PASSWORD=hunter2\n',
    },
    {
      name = 'json',
      parser = 'camouflage.parsers.json',
      content = '{\n  "api_key": "secret123",\n  "token": "abc(def)"\n}',
    },
    {
      name = 'json duplicate keys across objects',
      parser = 'camouflage.parsers.json',
      content = '{"a":{"password":"AAA"},"b":{"password":"BBB"},"c":{"password":"CCC"}}',
      expect_count = 3,
    },
    {
      name = 'json duplicate identical values across objects',
      parser = 'camouflage.parsers.json',
      content = '{"ab":{"password":"same"},"aa":{"password":"same"}}',
      expect_count = 2,
    },
    {
      name = 'yaml',
      parser = 'camouflage.parsers.yaml',
      content = 'api_key: secret123\ndb:\n  password: hunter2\n',
    },
    {
      name = 'toml',
      parser = 'camouflage.parsers.toml',
      content = 'api_key = "secret123"\ntoken = "abc123"\n',
    },
    {
      name = 'properties',
      parser = 'camouflage.parsers.properties',
      content = 'api.key=secret123\ndb.password=hunter2\n',
    },
    {
      name = 'netrc',
      parser = 'camouflage.parsers.netrc',
      content = 'machine github.com\nlogin myuser\npassword ghp_secret\n',
    },
    {
      name = 'netrc single line',
      parser = 'camouflage.parsers.netrc',
      content = 'machine x login admin password s3cr3t',
    },
  }

  for _, case in ipairs(cases) do
    it('holds the byte-offset contract for ' .. case.name, function()
      local parser = require(case.parser)
      local variables = parser.parse(case.content, nil)
      assert.is_true(#variables > 0, 'expected at least one variable for ' .. case.name)
      if case.expect_count then
        assert.equals(case.expect_count, #variables)
      end
      contract.assert_offsets(case.content, variables)
    end)
  end
end)
