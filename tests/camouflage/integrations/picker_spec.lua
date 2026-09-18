-- Picker result rows carry the matched line as text, so they are masked before
-- the picker draws them. The item keeps the real line, since opening or yanking
-- the hit has to work on the real text.
describe('camouflage.integrations.picker', function()
  local picker
  local config

  local function clear_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') or name:match('^snacks') or name:match('^telescope') then
        package.loaded[name] = nil
      end
    end
  end

  local function install_fake_snacks()
    local calls = {}
    package.loaded['snacks.picker.format'] = {
      file = function(item, pickr)
        table.insert(calls, { line = item.line, positions = item.positions, picker = pickr })
        return { { item.line or '', 'Normal' } }
      end,
    }
    return calls
  end

  local function install_fake_telescope()
    package.loaded['telescope.make_entry'] = {
      gen_from_vimgrep = function(_)
        return function(line)
          local filename, text = line:match('^([^:]+):%d+:%d+:(.*)$')
          return { filename = filename, text = text, value = line }
        end
      end,
    }
  end

  before_each(function()
    clear_modules()
    config = require('camouflage.config')
    config.setup({ style = 'stars', mask_char = '*' })
    require('camouflage.parsers').setup()
    picker = require('camouflage.integrations.picker')
    picker._reset()
  end)

  after_each(function()
    package.loaded['snacks.picker.format'] = nil
    package.loaded['telescope.make_entry'] = nil
    clear_modules()
  end)

  describe('mask_result', function()
    it('masks a matched line from a supported file', function()
      assert.equals(
        'API_KEY=************',
        picker.mask_result('/repo/.env', 'API_KEY=secret-value')
      )
    end)

    it('leaves files no parser handles alone', function()
      assert.is_nil(picker.mask_result('/repo/main.lua', 'local api_key = "secret-value"'))
    end)

    it('leaves a line without a value alone', function()
      assert.is_nil(picker.mask_result('/repo/.env', '# just a comment'))
    end)

    it('does nothing while masking is off', function()
      config.set('enabled', false)
      assert.is_nil(picker.mask_result('/repo/.env', 'API_KEY=secret-value'))
      config.set('enabled', true)
    end)

    it('does nothing when the integration is off', function()
      config.setup({ integrations = { picker_results = false } })
      require('camouflage.parsers').setup()
      assert.is_nil(picker.mask_result('/repo/.env', 'API_KEY=secret-value'))
    end)
  end)

  describe('snacks', function()
    it('masks the line the formatter receives', function()
      local calls = install_fake_snacks()
      picker.setup()

      local item = { file = '/repo/.env', line = 'API_KEY=secret-value', positions = { 1, 2 } }
      require('snacks.picker.format').file(item, {})

      assert.equals(1, #calls)
      assert.equals('API_KEY=************', calls[1].line)
      -- the item itself keeps the real line, so actions still work on it
      assert.equals('API_KEY=secret-value', item.line)
    end)

    it('drops match positions, which point into the old text', function()
      local calls = install_fake_snacks()
      picker.setup()

      require('snacks.picker.format').file(
        { file = '/repo/.env', line = 'API_KEY=secret-value', positions = { 1, 2 } },
        {}
      )

      assert.is_nil(calls[1].positions)
    end)

    it('passes rows it does not mask through untouched', function()
      local calls = install_fake_snacks()
      picker.setup()

      require('snacks.picker.format').file(
        { file = '/repo/main.lua', line = 'local api_key = "secret-value"', positions = { 3 } },
        {}
      )

      assert.equals('local api_key = "secret-value"', calls[1].line)
      assert.same({ 3 }, calls[1].positions)
    end)

    it('resolves a path relative to the picker cwd', function()
      local calls = install_fake_snacks()
      picker.setup()

      require('snacks.picker.format').file(
        { file = '.env', cwd = '/repo', line = 'API_KEY=secret-value' },
        {}
      )

      assert.equals('API_KEY=************', calls[1].line)
    end)

    it('wraps the formatter once', function()
      install_fake_snacks()
      picker.setup()
      local wrapped = require('snacks.picker.format').file
      picker.setup()
      assert.equals(wrapped, require('snacks.picker.format').file)
    end)
  end)

  describe('telescope', function()
    it('masks the text of a vimgrep entry', function()
      install_fake_telescope()
      picker.setup()

      local entry_maker = require('telescope.make_entry').gen_from_vimgrep({})
      local entry = entry_maker('/repo/.env:1:1:API_KEY=secret-value')

      assert.equals('API_KEY=************', entry.text)
      -- the raw line the entry was built from is untouched
      assert.equals('/repo/.env:1:1:API_KEY=secret-value', entry.value)
    end)

    it('leaves entries from other files alone', function()
      install_fake_telescope()
      picker.setup()

      local entry_maker = require('telescope.make_entry').gen_from_vimgrep({})
      local entry = entry_maker('/repo/main.lua:3:9:local api_key = "secret-value"')

      assert.equals('local api_key = "secret-value"', entry.text)
    end)
  end)
end)
