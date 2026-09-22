-- The shield is judged on what ends up on screen, so these run a real Neovim
-- and read its grid. Two editors for the whole file, one without a password
-- and one with, since every embedded editor is a process a CI runner has to
-- carry next to the rest of the suite.
local screen = dofile(vim.fn.getcwd() .. '/tests/camouflage/helpers/screen.lua')

-- The saved password lives in the data directory. Point it somewhere of our
-- own, for this process and the editors it starts, so a password set on the
-- machine running the tests can't change what they see.
vim.env.XDG_DATA_HOME = vim.fn.tempname()

describe('camouflage.shield', function()
  local shield

  before_each(function()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
    shield = require('camouflage.shield')
  end)

  describe('password hash', function()
    it('checks the password it was made from and nothing else', function()
      local hash = shield.hash_password('letmein')

      assert.truthy(hash:match('^sha256:%d+:%x+:%x+$'))
      assert.is_true(shield.verify_password('letmein', hash))
      assert.is_false(shield.verify_password('letmein ', hash))
      assert.is_false(shield.verify_password('', hash))
    end)

    it('salts every hash, so one password never gives the same string twice', function()
      assert.are_not.equal(shield.hash_password('same'), shield.hash_password('same'))
    end)

    it('never holds the password itself', function()
      assert.is_nil(shield.hash_password('findme'):find('findme', 1, true))
    end)

    it('refuses anything that is not one of its hashes', function()
      assert.is_nil(shield.parse_hash('letmein'))
      assert.is_nil(shield.parse_hash('sha256:10:abcd:1234'))
      assert.is_nil(shield.parse_hash(42))
      assert.is_false(shield.verify_password('letmein', 'letmein'))
    end)
  end)

  describe('saved password', function()
    before_each(function()
      require('camouflage').setup({ project_config = { enabled = false, watch_enabled = false } })
      shield.remove_password()
    end)

    after_each(function()
      shield.remove_password()
    end)

    it('applies as soon as it is saved, with nothing in the config', function()
      assert.is_false(shield.has_password())

      assert.is_true(shield.save_password(shield.hash_password('letmein')))

      assert.is_true(shield.has_password())
    end)

    it('keeps the hash readable by its owner only', function()
      shield.save_password(shield.hash_password('letmein'))

      assert.equals('rw-------', vim.fn.getfperm(shield.password_file()))
      assert.is_nil(table.concat(vim.fn.readfile(shield.password_file())):find('letmein', 1, true))
    end)

    it('lives in the data directory, not in a project', function()
      local data = vim.fn.stdpath('data')
      assert.equals(data, shield.password_file():sub(1, #data))
    end)

    it('refuses to save something that is not a hash', function()
      local ok = shield.save_password('letmein')

      assert.is_false(ok)
      assert.is_false(shield.has_password())
    end)

    it('goes away when removed', function()
      shield.save_password(shield.hash_password('letmein'))

      assert.is_true(shield.remove_password())
      assert.is_false(shield.has_password())
      assert.is_false(shield.remove_password(), 'removing twice should say there was nothing')
    end)

    it('gives way to shield.password_hash from setup()', function()
      local from_setup = shield.hash_password('fromsetup')
      shield.save_password(shield.hash_password('saved'))
      require('camouflage.config').get().shield.password_hash = from_setup

      assert.is_true(shield.has_password())
      require('camouflage.config').get().shield.password_hash = nil
    end)
  end)

  describe('on screen', function()
    local plain, locked

    local function has(session, text)
      return session:screen():find(text, 1, true) ~= nil
    end

    local function plain_session()
      if not plain then
        plain = screen.start({ height = 18, args = { 'tests/fixtures/test.env' } })
        assert.is_true(plain:wait_for('DATABASE_URL'), 'the file never appeared')
      end
      return plain
    end

    ---Started after the plain one is done with, since the password it saves is
    ---seen by every editor sharing the data directory.
    local function locked_session()
      if not locked then
        require('camouflage').setup({ project_config = { enabled = false, watch_enabled = false } })
        assert.is_true(shield.save_password(shield.hash_password('letmein')))
        locked = screen.start({ height = 18, args = { 'tests/fixtures/test.env' } })
        assert.is_true(locked:wait_for('DATABASE_URL'), 'the file never appeared')
      end
      return locked
    end

    it('covers everything, and the key that lifts it never reaches the buffer', function()
      local s = plain_session()

      s:request('nvim_input', ':CamouflageShield<CR>')
      assert.is_true(s:wait_for('press any key'))
      assert.is_false(has(s, 'DATABASE_URL'))
      assert.is_false(has(s, 'test.env'), 'the statusline shows through')

      s:request('nvim_input', 'x')
      assert.is_true(s:wait_for('DATABASE_URL'))
      assert.is_true(s:request('nvim_exec_lua', 'return not vim.bo.modified', {}))
    end)

    it('stays down when focus comes back, and when the editor grows', function()
      local s = plain_session()

      s:request('nvim_input', ':CamouflageShield<CR>')
      assert.is_true(s:wait_for('press any key'))

      s:request('nvim_ui_set_focus', false)
      s:settle(100)
      s:request('nvim_ui_set_focus', true)
      s:settle(200)
      assert.is_true(has(s, 'press any key'), '<FocusGained> lifted it')

      s:request('nvim_ui_try_resize', 100, 22)
      s:settle(300)
      assert.is_false(has(s, 'DATABASE_URL'))
      assert.is_false(has(s, 'DB_PASSWORD'))

      s:request('nvim_input', '<Esc>')
      assert.is_true(s:wait_for('DATABASE_URL'))
      s:request('nvim_ui_try_resize', 80, 18)
      s:settle(100)
    end)

    it('comes down on its own when focus is lost, if asked to', function()
      local s = plain_session()
      s:request(
        'nvim_exec_lua',
        [[
          require('camouflage.config').get().shield.on_focus_lost = true
          require('camouflage.shield').setup()
        ]],
        {}
      )

      s:request('nvim_ui_set_focus', false)
      assert.is_true(s:wait_for('press any key'))
      s:request('nvim_input', '<Esc>')
      assert.is_true(s:wait_for('DATABASE_URL'))

      s:request(
        'nvim_exec_lua',
        [[
          require('camouflage.config').get().shield.on_focus_lost = false
          require('camouflage.shield').setup()
        ]],
        {}
      )
      s:request('nvim_ui_set_focus', true)
    end)

    it('ignores a password hash it cannot read rather than locking for good', function()
      local s = plain_session()
      s:request(
        'nvim_exec_lua',
        [[require('camouflage.config').get().shield.password_hash = 'letmein']],
        {}
      )

      s:request('nvim_input', ':CamouflageShield<CR>')
      assert.is_true(s:wait_for('press any key'))
      s:request('nvim_input', 'q')
      assert.is_true(s:wait_for('DATABASE_URL'))

      s:request(
        'nvim_exec_lua',
        [[require('camouflage.config').get().shield.password_hash = nil]],
        {}
      )
    end)

    it('takes the password, not any key, when one is set', function()
      local s = locked_session()

      s:request('nvim_input', ':CamouflageShield<CR>')
      assert.is_true(s:wait_for('enter password'))

      s:request('nvim_input', '<Esc>')
      s:settle(100)
      assert.is_false(has(s, 'DATABASE_URL'), 'a single key lifted a locked shield')

      s:type('abc', 10)
      s:settle(100)
      assert.is_true(has(s, '•••·'), 'the typed characters are not shown as dots')
      assert.is_false(has(s, 'abc'), 'the password is drawn as typed')

      s:request('nvim_input', '<CR>')
      assert.is_true(s:wait_for('wrong password'))
      s:settle(800)
      assert.is_false(has(s, 'DATABASE_URL'))
    end)

    it('does not let <C-c> or <C-z> past the password', function()
      local s = locked_session()
      assert.is_true(has(s, 'enter password'), 'the previous test left it unlocked')

      s:request('nvim_input', '<C-c>')
      s:settle(300)
      assert.is_true(has(s, 'enter password'))
      assert.is_false(has(s, 'DATABASE_URL'))

      s:request('nvim_input', '<C-z>')
      s:settle(300)
      assert.is_true(has(s, 'enter password'))
      assert.is_false(has(s, 'DATABASE_URL'))
    end)

    it('lifts with the right password, <BS> included', function()
      local s = locked_session()

      s:type('letmeinz', 10)
      s:request('nvim_input', '<BS><CR>')
      assert.is_true(s:wait_for('DATABASE_URL'))
      assert.is_true(s:request('nvim_exec_lua', 'return not vim.bo.modified', {}))
    end)

    it('sets and removes the password from the command', function()
      local s = locked_session()

      s:request('nvim_input', ':CamouflageShieldPassword!<CR>')
      s:settle(200)
      assert.is_false(shield.has_password())

      s:request('nvim_input', ':CamouflageShieldPassword<CR>')
      s:type('opensesame', 5)
      s:request('nvim_input', '<CR>')
      s:type('opensesame', 5)
      s:request('nvim_input', '<CR>')
      s:settle(400)
      assert.is_true(shield.has_password())

      s:request('nvim_input', ':CamouflageShield<CR>')
      assert.is_true(s:wait_for('enter password'))
      s:type('opensesame', 5)
      s:request('nvim_input', '<CR>')
      assert.is_true(s:wait_for('DATABASE_URL'))

      shield.remove_password()
    end)

    it('leaves no editor running behind it', function()
      if plain then
        plain:stop()
      end
      if locked then
        locked:stop()
      end
      plain, locked = nil, nil
      assert.is_nil(plain)
    end)
  end)
end)
