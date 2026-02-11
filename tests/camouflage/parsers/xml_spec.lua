local xml_parser = require('camouflage.parsers.xml')

describe('camouflage.parsers.xml', function()
  before_each(function()
    require('camouflage.config').setup({
      parsers = {
        xml = {
          max_depth = 10,
        },
      },
    })
  end)

  describe('parse', function()
    it('should parse simple element content', function()
      local content = '<password>secret123</password>'
      local result = xml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('password', result[1].key)
      assert.equals('secret123', result[1].value)
    end)

    it('should parse multiple elements', function()
      local content = [[
<config>
  <username>admin</username>
  <password>secret</password>
  <host>localhost</host>
</config>
]]
      local result = xml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('admin', keys['config.username'])
      assert.equals('secret', keys['config.password'])
      assert.equals('localhost', keys['config.host'])
    end)

    it('should parse nested elements with path', function()
      local content = [[
<settings>
  <servers>
    <server>
      <id>my-repo</id>
      <password>secret123</password>
    </server>
  </servers>
</settings>
]]
      local result = xml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('my-repo', keys['settings.servers.server.id'])
      assert.equals('secret123', keys['settings.servers.server.password'])
    end)

    it('should parse attributes', function()
      local content = '<database host="localhost" password="dbpass" port="5432"/>'
      local result = xml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('localhost', keys['host'])
      assert.equals('dbpass', keys['password'])
      assert.equals('5432', keys['port'])
    end)

    it('should parse single-quoted attributes', function()
      local content = "<server host='localhost' password='secret'/>"
      local result = xml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('localhost', keys['host'])
      assert.equals('secret', keys['password'])
    end)

    it('should parse mixed elements and attributes', function()
      local content = [[
<settings>
  <database host="localhost" password="dbpass"/>
  <api>
    <key>api-secret-key</key>
  </api>
</settings>
]]
      local result = xml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('localhost', keys['host'])
      assert.equals('dbpass', keys['password'])
      assert.equals('api-secret-key', keys['settings.api.key'])
    end)

    it('should skip empty element values', function()
      local content = '<password></password>'
      local result = xml_parser.parse(content)

      -- Filter out any results for 'password' key
      local password_vars = {}
      for _, v in ipairs(result) do
        if v.key == 'password' then
          table.insert(password_vars, v)
        end
      end

      assert.equals(0, #password_vars)
    end)

    it('should skip whitespace-only element values', function()
      local content = '<password>   </password>'
      local result = xml_parser.parse(content)

      local password_vars = {}
      for _, v in ipairs(result) do
        if v.key == 'password' then
          table.insert(password_vars, v)
        end
      end

      assert.equals(0, #password_vars)
    end)

    it('should skip empty attribute values', function()
      local content = '<server password=""/>'
      local result = xml_parser.parse(content)

      local password_vars = {}
      for _, v in ipairs(result) do
        if v.key == 'password' then
          table.insert(password_vars, v)
        end
      end

      assert.equals(0, #password_vars)
    end)

    it('should handle empty content', function()
      local content = ''
      local result = xml_parser.parse(content)

      assert.equals(0, #result)
    end)

    it('should skip XML declaration attributes', function()
      local content = '<?xml version="1.0" encoding="UTF-8"?><root><key>value</key></root>'
      local result = xml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      -- version and encoding should not be parsed
      assert.is_nil(keys['version'])
      assert.is_nil(keys['encoding'])
      assert.equals('value', keys['root.key'])
    end)

    it('should parse Maven settings.xml style structure', function()
      local content = [[
<?xml version="1.0" encoding="UTF-8"?>
<settings>
  <servers>
    <server>
      <id>nexus-releases</id>
      <username>deployment</username>
      <password>deploy123</password>
    </server>
    <server>
      <id>nexus-snapshots</id>
      <username>snapshot-user</username>
      <password>snap456</password>
    </server>
  </servers>
</settings>
]]
      local result = xml_parser.parse(content)

      -- Should find multiple server configurations
      local passwords = {}
      for _, v in ipairs(result) do
        if v.value == 'deploy123' or v.value == 'snap456' then
          table.insert(passwords, v.value)
        end
      end

      assert.equals(2, #passwords)
    end)

    it('should parse pom.xml style structure', function()
      local content = [[
<project>
  <properties>
    <db.password>prodpass123</db.password>
  </properties>
  <build>
    <plugins>
      <plugin>
        <configuration>
          <apiKey>my-api-key</apiKey>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
]]
      local result = xml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('prodpass123', keys['project.properties.db.password'])
      assert.equals('my-api-key', keys['project.build.plugins.plugin.configuration.apiKey'])
    end)

    it('should handle self-closing tags', function()
      local content = [[
<config>
  <database host="localhost" port="5432"/>
  <password>secret</password>
</config>
]]
      local result = xml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('localhost', keys['host'])
      assert.equals('5432', keys['port'])
      assert.equals('secret', keys['config.password'])
    end)

    it('should handle elements with namespaces', function()
      local content = '<ns:password>secret</ns:password>'
      local result = xml_parser.parse(content)

      assert.equals(1, #result)
      assert.equals('ns:password', result[1].key)
      assert.equals('secret', result[1].value)
    end)

    it('should handle attributes with namespaces', function()
      local content = '<server xmlns:sec="http://example.com" sec:password="secret"/>'
      local result = xml_parser.parse(content)

      local keys = {}
      for _, v in ipairs(result) do
        keys[v.key] = v.value
      end

      assert.equals('secret', keys['sec:password'])
    end)

    it('should set correct line numbers', function()
      local content = [[
<root>
  <password>secret</password>
</root>
]]
      local result = xml_parser.parse(content)

      local password_var = nil
      for _, v in ipairs(result) do
        if v.value == 'secret' then
          password_var = v
          break
        end
      end

      assert.is_not_nil(password_var)
      assert.equals(1, password_var.line_number) -- 0-indexed: line 0=<root>, line 1=<password>
    end)

    it('should mark nested elements correctly', function()
      local content = [[
<root>
  <nested>
    <value>test</value>
  </nested>
</root>
]]
      local result = xml_parser.parse(content)

      local value_var = nil
      for _, v in ipairs(result) do
        if v.value == 'test' then
          value_var = v
          break
        end
      end

      assert.is_not_nil(value_var)
      assert.is_true(value_var.is_nested)
    end)
  end)

  describe('parse_regex', function()
    it('should work directly without TreeSitter', function()
      local content = '<password>secret123</password>'
      local result = xml_parser.parse_regex(content)

      assert.equals(1, #result)
      assert.equals('password', result[1].key)
      assert.equals('secret123', result[1].value)
    end)
  end)
end)
