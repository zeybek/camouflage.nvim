local dockerfile_parser = require('camouflage.parsers.dockerfile')

describe('camouflage.parsers.dockerfile', function()
  before_each(function()
    require('camouflage.config').setup({
      parsers = {
        include_commented = false,
        dockerfile = {},
      },
    })
  end)

  describe('parse', function()
    -- ENV tests
    describe('ENV instruction', function()
      it('should parse ENV KEY=value', function()
        local content = 'ENV API_KEY=secret123'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.equals('API_KEY', result[1].key)
        assert.equals('secret123', result[1].value)
      end)

      it('should parse ENV with double quoted value', function()
        local content = 'ENV SECRET="my secret value"'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.equals('SECRET', result[1].key)
        assert.equals('my secret value', result[1].value)
      end)

      it('should parse ENV with single quoted value', function()
        local content = "ENV SECRET='my secret value'"
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.equals('my secret value', result[1].value)
      end)

      it('should parse multiple ENV pairs on one line', function()
        local content = 'ENV KEY1=value1 KEY2=value2 KEY3=value3'
        local result = dockerfile_parser.parse(content)

        assert.equals(3, #result)
      end)

      it('should parse legacy ENV format (space separated)', function()
        local content = 'ENV MY_SECRET super_secret_value'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.equals('MY_SECRET', result[1].key)
        assert.equals('super_secret_value', result[1].value)
      end)

      it('should be case insensitive for ENV keyword', function()
        local content = 'env API_KEY=secret'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.equals('secret', result[1].value)
      end)
    end)

    -- ARG tests
    describe('ARG instruction', function()
      it('should parse ARG KEY=value', function()
        local content = 'ARG BUILD_SECRET=my_build_secret'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.equals('BUILD_SECRET', result[1].key)
        assert.equals('my_build_secret', result[1].value)
      end)

      it('should parse ARG with quoted value', function()
        local content = 'ARG CONFIG="config value here"'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.equals('config value here', result[1].value)
      end)

      it('should skip ARG without default value', function()
        local content = 'ARG RUNTIME_SECRET'
        local result = dockerfile_parser.parse(content)

        assert.equals(0, #result)
      end)

      it('should be case insensitive for ARG keyword', function()
        local content = 'arg MY_ARG=value'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
      end)
    end)

    -- LABEL tests
    describe('LABEL instruction', function()
      it('should parse LABEL key=value', function()
        local content = 'LABEL maintainer="dev@example.com"'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.equals('maintainer', result[1].key)
        assert.equals('dev@example.com', result[1].value)
      end)

      it('should parse multiple LABEL pairs', function()
        local content = 'LABEL version="1.0" author="test"'
        local result = dockerfile_parser.parse(content)

        assert.equals(2, #result)
      end)

      it('should parse LABEL with dotted key', function()
        local content = 'LABEL com.example.secret="secret_value"'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.equals('com.example.secret', result[1].key)
      end)

      it('should be case insensitive for LABEL keyword', function()
        local content = 'label key=value'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
      end)
    end)

    -- Comment tests
    describe('comments', function()
      it('should skip commented lines by default', function()
        local content = '# ENV SECRET=hidden'
        local result = dockerfile_parser.parse(content)

        assert.equals(0, #result)
      end)

      it('should parse commented lines when enabled', function()
        require('camouflage.config').setup({
          parsers = {
            include_commented = true,
            dockerfile = {},
          },
        })

        local content = '# ENV SECRET=hidden'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        assert.is_true(result[1].is_commented)
      end)
    end)

    -- Edge cases
    describe('edge cases', function()
      it('should handle empty content', function()
        local content = ''
        local result = dockerfile_parser.parse(content)

        assert.equals(0, #result)
      end)

      it('should skip non-ENV/ARG/LABEL lines', function()
        local content = [[
FROM alpine:latest
WORKDIR /app
RUN echo "hello"
COPY . .
EXPOSE 3000
]]
        local result = dockerfile_parser.parse(content)

        assert.equals(0, #result)
      end)

      it('should handle mixed instructions', function()
        local content = [[
FROM alpine
ARG BUILD_KEY=build123
ENV APP_SECRET=app456
LABEL api.key="label789"
]]
        local result = dockerfile_parser.parse(content)

        assert.equals(3, #result)
      end)
    end)

    -- Position accuracy
    describe('position accuracy', function()
      it('should calculate correct byte positions for ENV', function()
        local content = 'ENV KEY=value'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        -- "value" starts at position 8 (0-indexed)
        assert.equals(8, result[1].start_index)
        assert.equals(13, result[1].end_index)
      end)

      it('should calculate correct positions for quoted values', function()
        local content = 'ENV KEY="value"'
        local result = dockerfile_parser.parse(content)

        assert.equals(1, #result)
        -- "value" (without quotes) starts at position 9
        assert.equals(9, result[1].start_index)
        assert.equals(14, result[1].end_index)
      end)
    end)
  end)
end)
