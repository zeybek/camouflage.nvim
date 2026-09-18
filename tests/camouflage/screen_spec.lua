-- What ends up on screen, read from a real Neovim's grid rather than from
-- extmarks. A mask that lands after the redraw still satisfies an extmark
-- assertion while the value was already drawn, and this is the difference.
--
-- Every session is a Neovim process of its own, so the scenarios share one:
-- seven editors at once is a lot to ask of a CI runner that is already running
-- the rest of the suite next to this.
local screen = dofile(vim.fn.getcwd() .. '/tests/camouflage/helpers/screen.lua')

describe('camouflage on screen', function()
  local dir
  local envfile
  local luafile
  local sessions = {}

  ---Files the sessions open, written once.
  local function fixtures()
    if dir then
      return
    end
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    envfile = dir .. '/.env'
    luafile = dir .. '/config.lua'
    vim.fn.writefile({ 'OPEN_KEY=OPENSECRETVALUE' }, envfile)
    vim.fn.writefile({ 'local token = "PLAINSOURCEVALUE"' }, luafile)
  end

  ---The session showing a file, started on first use.
  local function session_for(file)
    fixtures()
    if not sessions[file] then
      sessions[file] = screen.start({ args = { file } })
    end
    return sessions[file]
  end

  local function env()
    fixtures()
    return session_for(envfile)
  end

  it('draws the file masked on the very first frame', function()
    local session = env()
    assert.is_true(session:wait_for('OPEN_KEY='), 'the file never appeared on screen')

    assert.equals(0, session:frames_with('OPENSECRETVALUE'))
    assert.is_not_nil(session:screen():find('*', 1, true))
  end)

  it('never draws a value while it is typed', function()
    local session = env()
    local from = session:mark()

    session:feed('Go')
    session:type('TYPED_KEY=TYPEDSECRETVALUE')
    session:feed('<Esc>')

    assert.equals(0, session:frames_with('TYPEDSECRET', from))
    assert.is_not_nil(session:screen():find('TYPED_KEY=', 1, true))
  end)

  it('never draws characters appended to a value that is already masked', function()
    local session = env()
    local from = session:mark()

    session:feed('1G$a')
    session:type('APPENDED')
    session:feed('<Esc>')

    -- The appended characters sit past the end of the old mask, which is where
    -- they used to show up one at a time.
    assert.equals(0, session:frames_with('APPENDED', from))
    assert.equals(0, session:frames_with('APPEN', from))
  end)

  it('never draws a value put from a register', function()
    local session = env()
    local from = session:mark()

    session:request('nvim_exec_lua', "vim.fn.setreg('a', {'PUT_KEY=PUTSECRETVALUE'}, 'l')", {})
    session:feed('G"ap')
    session:settle(400)

    assert.equals(0, session:frames_with('PUTSECRETVALUE', from))
  end)

  it('never draws a pasted value', function()
    local session = env()
    local from = session:mark()

    session:feed('Go')
    session:request(
      'nvim_paste',
      'PASTE_KEY=PASTESECRETVALUE\nPASTE2_KEY=SECONDPASTEVALUE',
      false,
      -1
    )
    session:feed('<Esc>')
    session:settle(400)

    assert.equals(0, session:frames_with('PASTESECRETVALUE', from))
    assert.equals(0, session:frames_with('SECONDPASTEVALUE', from))
  end)

  it('leaves a file no parser handles alone', function()
    local session = session_for(luafile)

    assert.is_true(session:wait_for('PLAINSOURCEVALUE'), 'the source file was never drawn')
  end)

  -- Last of the scenarios, because it puts a value on screen on purpose. It
  -- also proves the harness can see a value when there is one, which is what
  -- makes every assertion above mean something.
  it('draws a value again once the line is revealed', function()
    local session = env()
    local from = session:mark()

    session:request('nvim_command', '1')
    session:request('nvim_command', 'CamouflageReveal')
    session:settle(300)

    assert.is_true(
      session:frames_with('OPENSECRETVALUE', from) > 0,
      'reveal should put the value back on screen'
    )
  end)

  it('leaves no editor running behind it', function()
    for file, session in pairs(sessions) do
      session:stop()
      sessions[file] = nil
    end
    if dir then
      vim.fn.delete(dir, 'rf')
    end

    assert.same({}, sessions)
  end)
end)
