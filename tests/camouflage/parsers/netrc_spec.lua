local netrc_parser = require('camouflage.parsers.netrc')

describe('camouflage.parsers.netrc', function()
  describe('parse', function()
    it('should parse multi-line format', function()
      local content = [[
machine github.com
login myusername
password ghp_xxxxxxxxxxxx
]]
      local result = netrc_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('login', result[1].key)
      assert.equals('myusername', result[1].value)
      assert.equals('password', result[2].key)
      assert.equals('ghp_xxxxxxxxxxxx', result[2].value)
    end)

    it('should parse single-line format', function()
      local content = 'machine gitlab.com login oauth2 password glpat-xxxxx'
      local result = netrc_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('login', result[1].key)
      assert.equals('oauth2', result[1].value)
      assert.equals('password', result[2].key)
      assert.equals('glpat-xxxxx', result[2].value)
    end)

    it('should parse account keyword', function()
      local content = [[
machine ftp.example.com
login user
password secret
account premium
]]
      local result = netrc_parser.parse(content)

      assert.equals(3, #result)
      assert.equals('login', result[1].key)
      assert.equals('password', result[2].key)
      assert.equals('account', result[3].key)
      assert.equals('premium', result[3].value)
    end)

    it('should parse default keyword', function()
      local content = 'default login anonymous password guest@example.com'
      local result = netrc_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('anonymous', result[1].value)
      assert.equals('guest@example.com', result[2].value)
    end)

    it('should parse quoted values', function()
      local content = 'machine server.com login "user with spaces" password "secret password"'
      local result = netrc_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('user with spaces', result[1].value)
      assert.equals('secret password', result[2].value)
    end)

    it('should parse single quoted values', function()
      local content = "machine server.com login 'quoted_user' password 'quoted_pass'"
      local result = netrc_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('quoted_user', result[1].value)
      assert.equals('quoted_pass', result[2].value)
    end)

    it('should handle multiple machines', function()
      local content = [[
machine github.com login user1 password pass1
machine gitlab.com login user2 password pass2
machine bitbucket.org login user3 password pass3
]]
      local result = netrc_parser.parse(content)

      assert.equals(6, #result)
      assert.equals('user1', result[1].value)
      assert.equals('pass1', result[2].value)
      assert.equals('user2', result[3].value)
      assert.equals('pass2', result[4].value)
      assert.equals('user3', result[5].value)
      assert.equals('pass3', result[6].value)
    end)

    it('should skip comment lines', function()
      local content = [[
# This is a comment
machine github.com
login user
password secret
# Another comment
]]
      local result = netrc_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('user', result[1].value)
      assert.equals('secret', result[2].value)
    end)

    it('should handle empty file', function()
      local result = netrc_parser.parse('')
      assert.are.same({}, result)
    end)

    it('should handle machine without credentials', function()
      local content = 'machine example.com'
      local result = netrc_parser.parse(content)

      assert.equals(0, #result)
    end)

    it('should handle mixed format', function()
      local content = [[
machine mixed.example.com login mixeduser
password mixedsecret
]]
      local result = netrc_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('mixeduser', result[1].value)
      assert.equals('mixedsecret', result[2].value)
    end)

    it('should be case-insensitive for keywords', function()
      local content = 'machine server.com LOGIN user PASSWORD secret'
      local result = netrc_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('login', result[1].key)
      assert.equals('password', result[2].key)
    end)

    it('should handle tabs as separators', function()
      local content = "machine\tserver.com\tlogin\tuser\tpassword\tsecret"
      local result = netrc_parser.parse(content)

      assert.equals(2, #result)
      assert.equals('user', result[1].value)
      assert.equals('secret', result[2].value)
    end)
  end)
end)
