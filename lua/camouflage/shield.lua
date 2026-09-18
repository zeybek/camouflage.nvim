---@mod camouflage.shield Cover the whole editor

-- Masking hides values one at a time. Sometimes the whole screen is the
-- problem: you step away mid-share, or switch to another app while the editor
-- is still in the shared area. This covers everything Neovim draws with one
-- opaque window until a key is pressed.
--
-- The cover is a camouflage pattern, generated fresh every time, with a small
-- card in the middle saying what happened.
--
-- The key is read here rather than by the window, so whatever is typed while
-- the editor is covered never reaches the buffer underneath.
--
-- With a password set, any key is not enough: the password is typed onto the
-- card and checked against a salted, stretched SHA-256. :CamouflageShieldPassword
-- keeps that hash in Neovim's data directory, so it applies at once and in
-- every project without touching the config. The password itself is kept
-- nowhere. It is a deterrent, not a lock: whoever is at the keyboard can still
-- close the terminal.

local M = {}

local config = require('camouflage.config')

local DEFAULT_TEXT = 'screen hidden\npress any key'
local DEFAULT_LOCKED_TEXT = 'screen locked\nenter password'

-- SHA-256 applied this many times. About 90 ms on a laptop: nothing when
-- unlocking, a lot for someone trying every word in a list.
local ROUNDS = 50000

-- Pause after a wrong password, so guessing by hand is slow too.
local WRONG_PAUSE_MS = 600

-- Above the builtin UI (messages are 200, the cmdline popup 250) and above
-- what pickers, notifiers and key hint popups use.
local ZINDEX = 30000

-- How often the wait loop looks for a key and for a resized editor.
local POLL_MS = 30

-- Keys that arrive without anyone pressing one. Coming back to the terminal
-- sends <FocusGained>, and that must not be what uncovers the screen.
local NOT_A_KEYPRESS = {
  ['<FocusGained>'] = true,
  ['<FocusLost>'] = true,
  ['<Ignore>'] = true,
  ['<CursorHold>'] = true,
  ['<MouseMove>'] = true,
}

-- Woodland: dark green, olive, brown and near black. Each is a highlight group
-- linked by default, so a colorscheme or the user can repaint it.
local PATTERN = {
  { name = 'CamouflageShield1', bg = '#1f2418', ctermbg = 234 },
  { name = 'CamouflageShield2', bg = '#3d4a28', ctermbg = 58 },
  { name = 'CamouflageShield3', bg = '#5a4630', ctermbg = 94 },
  { name = 'CamouflageShield4', bg = '#2c3320', ctermbg = 236 },
}

-- Where the noise is cut into the four colors. Value noise clusters around
-- the middle, so the cuts do too, or one color would take most of the screen.
local BANDS = { 0.42, 0.5, 0.58 }

-- Size of a blob in cells. Terminal cells are about twice as tall as they are
-- wide, so rows are stretched to keep the blobs from looking squashed.
local SCALE = 11
local ROW_STRETCH = 2

local ns = vim.api.nvim_create_namespace('camouflage_shield')

---@type table|nil
local current

---@type number|nil
local group

---@return table
local function shield_config()
  return config.get().shield or {}
end

---@return boolean
function M.is_open()
  return current ~= nil
end

---@param password string
---@param salt string
---@param rounds number
---@return string
local function derive(password, salt, rounds)
  local digest = salt .. password
  for _ = 1, rounds do
    digest = vim.fn.sha256(digest)
  end
  return digest
end

---Split a stored hash into its parts. Nil when it isn't one.
---@param stored any
---@return number|nil rounds
---@return string|nil salt
---@return string|nil digest
function M.parse_hash(stored)
  if type(stored) ~= 'string' then
    return nil
  end
  local rounds, salt, digest = stored:match('^sha256:(%d+):(%x+):(%x+)$')
  if not rounds or #digest ~= 64 or tonumber(rounds) < 1 then
    return nil
  end
  return tonumber(rounds), salt, digest
end

---The stored form of a password: salt and digest, never the password.
---@param password string
---@return string
function M.hash_password(password)
  local salt = vim.fn.sha256(tostring(vim.loop.hrtime()) .. tostring(math.random())):sub(1, 16)
  return string.format('sha256:%d:%s:%s', ROUNDS, salt, derive(password, salt, ROUNDS))
end

---@param password string
---@param stored string
---@return boolean
function M.verify_password(password, stored)
  local rounds, salt, digest = M.parse_hash(stored)
  if not rounds then
    return false
  end
  return derive(password, salt, rounds) == digest
end

---Where :CamouflageShieldPassword keeps the hash: per user, not per project.
---@return string
function M.password_file()
  return vim.fn.stdpath('data') .. '/camouflage/shield_password'
end

---@return string|nil
local function stored_hash()
  local path = M.password_file()
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path, '', 1)
  if not ok or not lines[1] or lines[1] == '' then
    return nil
  end
  return lines[1]
end

---Keep a hash as the password from now on, for every session.
---@param hash string
---@return boolean ok
---@return string|nil err
function M.save_password(hash)
  if not M.parse_hash(hash) then
    return false, 'not a shield password hash'
  end
  local path = M.password_file()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local ok, err = pcall(vim.fn.writefile, { hash }, path)
  if not ok then
    return false, tostring(err)
  end
  vim.fn.setfperm(path, 'rw-------')
  return true
end

---Remove the saved password. Returns false when there was none.
---@return boolean
function M.remove_password()
  local path = M.password_file()
  if vim.fn.filereadable(path) == 0 then
    return false
  end
  return vim.fn.delete(path) == 0
end

---The hash in effect, or nil. `shield.password_hash` in setup() wins over the
---saved one. A malformed one is refused rather than used: it would match
---nothing and lock the editor for good.
---@return string|nil
local function password_hash()
  local stored = shield_config().password_hash
  local source = 'shield.password_hash'
  if stored == nil or stored == '' then
    stored, source = stored_hash(), M.password_file()
  end
  if stored == nil then
    return nil
  end
  if not M.parse_hash(stored) then
    vim.notify_once(
      string.format('[camouflage] %s does not hold a shield password hash, ignoring it', source),
      vim.log.levels.WARN
    )
    return nil
  end
  return stored
end

---Whether the shield asks for a password right now.
---@return boolean
function M.has_password()
  return password_hash() ~= nil
end

---@return nil
local function set_highlights()
  for _, color in ipairs(PATTERN) do
    vim.api.nvim_set_hl(0, color.name, { default = true, bg = color.bg, ctermbg = color.ctermbg })
  end
  vim.api.nvim_set_hl(0, 'CamouflageShieldCard', { default = true, link = 'NormalFloat' })
  vim.api.nvim_set_hl(0, 'CamouflageShieldBorder', { default = true, link = 'FloatBorder' })
  vim.api.nvim_set_hl(0, 'CamouflageShieldTitle', { default = true, link = 'Title' })
  vim.api.nvim_set_hl(0, 'CamouflageShieldText', { default = true, link = 'Comment' })
  vim.api.nvim_set_hl(0, 'CamouflageShieldInput', { default = true, link = 'Normal' })
  vim.api.nvim_set_hl(0, 'CamouflageShieldError', { default = true, link = 'ErrorMsg' })
end

---A shuffled 0..255 table: the seed of one pattern.
---@return number[]
local function permutation()
  local perm = {}
  for i = 0, 255 do
    perm[i] = i
  end
  for i = 255, 1, -1 do
    local j = math.random(0, i)
    perm[i], perm[j] = perm[j], perm[i]
  end
  return perm
end

---@param perm number[]
---@param x number
---@param y number
---@return number 0..1
local function lattice(perm, x, y)
  return perm[(perm[x % 256] + y) % 256] / 255
end

---@param t number
---@return number
local function smooth(t)
  return t * t * (3 - 2 * t)
end

---Smooth value noise at a point.
---@param perm number[]
---@param x number
---@param y number
---@return number 0..1
local function noise(perm, x, y)
  local x0, y0 = math.floor(x), math.floor(y)
  local tx, ty = smooth(x - x0), smooth(y - y0)
  local a = lattice(perm, x0, y0)
  local b = lattice(perm, x0 + 1, y0)
  local c = lattice(perm, x0, y0 + 1)
  local d = lattice(perm, x0 + 1, y0 + 1)
  local top = a + (b - a) * tx
  local bottom = c + (d - c) * tx
  return top + (bottom - top) * ty
end

---Which of the four colors a cell gets. Two octaves: big blobs with ragged
---edges, which is what makes it read as camouflage rather than as clouds.
---@param perm number[]
---@param col number
---@param row number
---@return number 1..4
local function band_at(perm, col, row)
  local x, y = col / SCALE, row * ROW_STRETCH / SCALE
  local value = noise(perm, x, y) * 0.7 + noise(perm, x * 2.7 + 31, y * 2.7 + 17) * 0.3
  for i, cut in ipairs(BANDS) do
    if value < cut then
      return i
    end
  end
  return #PATTERN
end

---Paint the pattern into the cover buffer for the current editor size.
---@param buf number
---@param perm number[]
---@param width number
---@param height number
---@return nil
local function paint(buf, perm, width, height)
  local blank = string.rep(' ', width)
  local lines = {}
  for i = 1, height do
    lines[i] = blank
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- One mark per run of the same color, not one per cell.
  for row = 0, height - 1 do
    local start, band = 0, nil
    for col = 0, width do
      local here = col < width and band_at(perm, col, row) or nil
      if here ~= band then
        if band then
          vim.api.nvim_buf_set_extmark(buf, ns, row, start, {
            end_col = col,
            hl_group = PATTERN[band].name,
          })
        end
        start, band = col, here
      end
    end
  end
end

-- Room on the card for the password as it is typed.
local INPUT_WIDTH = 20

---The card's text lines, and where the input and status rows are when locked.
---@param locked boolean
---@param typed number characters typed so far
---@param status string|nil
---@return string[] lines
---@return table rows { text = number[], input = number|nil, status = number|nil } 0-indexed
local function card_lines(locked, typed, status)
  local text = shield_config().text or (locked and DEFAULT_LOCKED_TEXT or DEFAULT_TEXT)
  local lines, rows = { '' }, { text = {} }
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    table.insert(rows.text, #lines)
    table.insert(lines, '   ' .. line .. '   ')
  end
  if locked then
    table.insert(lines, '')
    rows.input = #lines
    local shown = math.min(typed, INPUT_WIDTH)
    table.insert(lines, '   ' .. string.rep('•', shown) .. string.rep('·', INPUT_WIDTH - shown))
    rows.status = #lines
    table.insert(lines, '   ' .. (status or ''))
  end
  table.insert(lines, '')
  return lines, rows
end

---Where the card goes and how big it is, for the current editor size.
---@param lines string[]
---@return table
local function card_config(lines)
  local width = #' camouflage ' + 4
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 3)
  end
  local height = #lines
  return {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
  }
end

---Write the card's text for the current state.
---@param typed number
---@param status string|nil
---@return nil
local function render_card(typed, status)
  local lines, rows = card_lines(current.locked, typed, status)
  local buf = current.card_buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  -- From the text, not the indent: a group with a background would otherwise
  -- paint a bar from the edge of the card.
  local function paint_row(row, group_name)
    local line = lines[row + 1]
    local start = (line:find('%S') or 1) - 1
    vim.api.nvim_buf_set_extmark(buf, ns, row, start, { end_col = #line, hl_group = group_name })
  end
  for _, row in ipairs(rows.text) do
    paint_row(row, 'CamouflageShieldText')
  end
  if rows.input then
    paint_row(rows.input, 'CamouflageShieldInput')
  end
  if rows.status and status then
    paint_row(rows.status, 'CamouflageShieldError')
  end
  current.lines = lines
end

---@param locked boolean
---@return table
local function open_windows(locked)
  set_highlights()

  local width, height = vim.o.columns, vim.o.lines
  local perm = permutation()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  paint(buf, perm, width, height)

  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 0,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    -- 'winborder' (0.11+) would otherwise put a border on it, which pushes the
    -- window past the edge of the editor.
    border = 'none',
    focusable = false,
    zindex = ZINDEX,
    noautocmd = true,
  })
  -- A global 'winblend' would make it see-through, which defeats the point.
  vim.wo[win].winblend = 0

  local lines = card_lines(locked, 0, nil)
  local card_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[card_buf].bufhidden = 'wipe'

  local card = vim.tbl_extend('force', card_config(lines), {
    style = 'minimal',
    border = 'rounded',
    title = ' camouflage ',
    title_pos = 'center',
    focusable = false,
    zindex = ZINDEX + 1,
    noautocmd = true,
  })
  local card_win = vim.api.nvim_open_win(card_buf, false, card)
  vim.wo[card_win].winblend = 0
  vim.wo[card_win].winhighlight = table.concat({
    'Normal:CamouflageShieldCard',
    'FloatBorder:CamouflageShieldBorder',
    'FloatTitle:CamouflageShieldTitle',
  }, ',')

  return {
    win = win,
    buf = buf,
    card_win = card_win,
    card_buf = card_buf,
    lines = lines,
    locked = locked,
    perm = perm,
    width = width,
    height = height,
  }
end

---Follow a resized editor, so a bigger terminal doesn't uncover an edge.
---@return nil
local function fit()
  if not current or not vim.api.nvim_win_is_valid(current.win) then
    return
  end
  local width, height = vim.o.columns, vim.o.lines
  if width == current.width and height == current.height then
    return
  end
  vim.api.nvim_win_set_config(current.win, {
    relative = 'editor',
    row = 0,
    col = 0,
    width = width,
    height = height,
  })
  -- Same seed, so the pattern grows at the edge instead of reshuffling.
  paint(current.buf, current.perm, width, height)
  if vim.api.nvim_win_is_valid(current.card_win) then
    vim.api.nvim_win_set_config(current.card_win, card_config(current.lines))
  end
  current.width, current.height = width, height
  vim.cmd('redraw')
end

---Next key, or nil when there is none yet. Keys that nobody pressed are
---dropped here. `interrupted` is true for <C-c>.
---@return string|nil key
---@return boolean interrupted
local function next_key()
  local ok, key = pcall(vim.fn.getcharstr, 0)
  if not ok then
    return nil, true
  end
  if key == '' then
    fit()
    local _, code = vim.wait(POLL_MS)
    return nil, code == -2
  end
  if NOT_A_KEYPRESS[vim.fn.keytrans(key)] then
    return nil, false
  end
  return key, false
end

---Wait for one real keypress and swallow it.
---@return nil
local function wait_for_key()
  while current do
    local key, interrupted = next_key()
    if key or interrupted then
      return
    end
  end
end

---A key that types a character, rather than a special or control key.
---@param key string
---@return boolean
local function is_character(key)
  local byte = key:byte(1)
  return byte ~= nil and byte >= 32 and byte ~= 127 and byte ~= 0x80
end

---Take the password on the card until it matches. <C-c> does not get past it.
---@param stored string
---@return nil
local function wait_for_password(stored)
  local typed = {}
  while current do
    local key = next_key()
    if key then
      local name = vim.fn.keytrans(key)
      local status
      if name == '<CR>' or name == '<NL>' or name == '<kEnter>' then
        if M.verify_password(table.concat(typed), stored) then
          return
        end
        typed = {}
        status = 'wrong password'
        render_card(0, status)
        vim.cmd('redraw')
        vim.wait(WRONG_PAUSE_MS)
        -- What was typed during the pause doesn't count.
        local drained
        repeat
          local ok, pending = pcall(vim.fn.getcharstr, 0)
          drained = not ok or pending == ''
        until drained
      elseif name == '<BS>' or name == '<C-H>' then
        table.remove(typed)
      elseif name == '<C-U>' or name == '<Esc>' then
        typed = {}
      elseif is_character(key) then
        table.insert(typed, key)
      end
      render_card(#typed, status)
      vim.cmd('redraw')
    end
  end
end

---Remove the cover.
---@return boolean closed false when it wasn't open
function M.close()
  if not current then
    return false
  end
  pcall(vim.api.nvim_win_close, current.card_win, true)
  pcall(vim.api.nvim_win_close, current.win, true)
  current = nil
  vim.cmd('redraw')
  return true
end

---Cover the editor and wait for a key, or for the password when one is set.
---Returns once it has been uncovered.
---@return boolean opened false when it was already open
function M.open()
  if current then
    return false
  end
  local stored = password_hash()
  current = open_windows(stored ~= nil)
  render_card(0, nil)
  vim.cmd('redraw')
  if stored then
    wait_for_password(stored)
  else
    wait_for_key()
  end
  M.close()
  return true
end

---Ask for a password twice and return the hash for the config, or nil.
---@return string|nil
function M.prompt_password()
  local ok, first = pcall(vim.fn.inputsecret, 'New shield password: ')
  if not ok or first == '' then
    return nil
  end
  local ok2, second = pcall(vim.fn.inputsecret, 'Again: ')
  if not ok2 then
    return nil
  end
  if first ~= second then
    vim.notify('[camouflage] the two passwords differ, nothing changed', vim.log.levels.WARN)
    return nil
  end
  return M.hash_password(first)
end

---Wire the automatic triggers from config. Safe to call again after a reload.
---@return nil
function M.setup()
  if group then
    vim.api.nvim_del_augroup_by_id(group)
    group = nil
  end
  if not shield_config().on_focus_lost then
    return
  end

  group = vim.api.nvim_create_augroup('CamouflageShield', { clear = true })
  vim.api.nvim_create_autocmd('FocusLost', {
    group = group,
    callback = function()
      -- Not from inside the autocmd: the wait loop would hold it open.
      vim.schedule(M.open)
    end,
  })
end

---Internal: drop state (used by tests).
---@return nil
function M._reset()
  if current then
    pcall(vim.api.nvim_win_close, current.card_win, true)
    pcall(vim.api.nvim_win_close, current.win, true)
  end
  current = nil
end

return M
