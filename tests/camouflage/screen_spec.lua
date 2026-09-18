-- What ends up on screen, read from a real Neovim's grid rather than from
-- extmarks. A mask that lands after the redraw still satisfies an extmark
-- assertion while the value was already drawn, and this is the difference.
local screen = dofile(vim.fn.getcwd() .. '/tests/camouflage/helpers/screen.lua')

describe('camouflage on screen', function()
  local session
  local dir
  local envfile

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    envfile = dir .. '/.env'
    vim.fn.writefile({ 'OPEN_KEY=OPENSECRETVALUE' }, envfile)
  end)

  after_each(function()
    if session then
      session:stop()
      session = nil
    end
    vim.fn.delete(dir, 'rf')
  end)

  it('never draws a value while it is typed', function()
    session = screen.start({ args = { envfile } })
    assert.is_true(session:wait_for('OPEN_KEY='), 'the file never appeared on screen')
    assert.equals(0, session:frames_with('OPENSECRETVALUE'))

    local from = session:mark()
    session:feed('Go')
    session:type('TYPED_KEY=TYPEDSECRETVALUE')
    session:feed('<Esc>')

    assert.equals(0, session:frames_with('TYPEDSECRET', from))
    assert.is_not_nil(session:screen():find('TYPED_KEY=', 1, true))
  end)

  it('never draws characters appended to a value that is already masked', function()
    session = screen.start({ args = { envfile } })
    assert.is_true(session:wait_for('OPEN_KEY='))

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
    session = screen.start({ args = { envfile } })
    assert.is_true(session:wait_for('OPEN_KEY='))

    local from = session:mark()
    session:request('nvim_exec_lua', "vim.fn.setreg('a', {'PUT_KEY=PUTSECRETVALUE'}, 'l')", {})
    session:feed('G"ap')
    session:settle(400)

    assert.equals(0, session:frames_with('PUTSECRETVALUE', from))
  end)

  it('never draws a pasted value', function()
    session = screen.start({ args = { envfile } })
    assert.is_true(session:wait_for('OPEN_KEY='))

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

  it('draws the file masked on the very first frame', function()
    session = screen.start({ args = { envfile } })
    assert.is_true(session:wait_for('OPEN_KEY='), 'the file never appeared on screen')

    assert.equals(0, session:frames_with('OPENSECRETVALUE'))
    assert.is_not_nil(session:screen():find('OPEN_KEY=', 1, true))
    assert.is_not_nil(session:screen():find('*', 1, true))
  end)

  it('draws a value again once the line is revealed', function()
    session = screen.start({ args = { envfile } })
    assert.is_true(session:wait_for('OPEN_KEY='))
    assert.equals(0, session:frames_with('OPENSECRETVALUE'))

    session:request('nvim_command', 'CamouflageReveal')
    session:settle(300)

    assert.is_true(session:frames_with('OPENSECRETVALUE') > 0, 'reveal should show the value')
  end)

  it('leaves a file no parser handles alone', function()
    local luafile = dir .. '/config.lua'
    vim.fn.writefile({ 'local token = "PLAINSOURCEVALUE"' }, luafile)
    session = screen.start({ args = { luafile } })

    assert.is_true(session:wait_for('PLAINSOURCEVALUE'), 'the source file was never drawn')
  end)
end)
