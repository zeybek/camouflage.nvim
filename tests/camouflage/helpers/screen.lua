-- Test helper: run a real Neovim with the plugin loaded, attach a UI to it, and
-- keep every frame it draws.
--
-- The rest of the suite asserts on extmarks, which is a proxy: a mark placed
-- after the redraw satisfies it while the value was already on screen. This
-- reads the grid the way a terminal would, so "was the value ever drawn" can be
-- answered directly.
--
-- Talks msgpack-RPC over a pipe, the same protocol a GUI uses. vim.uv/vim.loop
-- and vim.mpack ship with every supported Neovim, so there is nothing to
-- install.

local uv = vim.uv or vim.loop

local M = {}

local Session = {}
Session.__index = Session

---@param opts table|nil
---   width, height: grid size (default 80x16)
---   args: extra command line arguments for the child (e.g. a file to open)
---   config: camouflage setup options, as a Lua literal string
---@return table
function M.start(opts)
  opts = opts or {}
  local width = opts.width or 80
  local height = opts.height or 16

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local init = dir .. '/init.lua'
  vim.fn.writefile({
    ('vim.opt.rtp:prepend(%q)'):format(vim.fn.getcwd()),
    'vim.cmd("filetype on")',
    'vim.o.shadafile = "NONE"',
    'vim.o.swapfile = false',
    'vim.o.laststatus = 0',
    'vim.o.ruler = false',
    ('require("camouflage").setup(%s)'):format(
      opts.config or '{ project_config = { enabled = false, watch_enabled = false } }'
    ),
  }, init)

  local args = { '--embed', '--clean', '-u', init }
  for _, arg in ipairs(opts.args or {}) do
    table.insert(args, arg)
  end

  local self = setmetatable({
    dir = dir,
    width = width,
    height = height,
    frames = {},
    responses = {},
    msgid = 0,
    grid = {},
    buffer = '',
    unpacker = vim.mpack.Unpacker(),
  }, Session)

  for row = 1, height do
    self.grid[row] = {}
    for col = 1, width do
      self.grid[row][col] = ' '
    end
  end

  self.stdin, self.stdout = uv.new_pipe(false), uv.new_pipe(false)
  self.proc = uv.spawn(vim.v.progpath, {
    args = args,
    stdio = { self.stdin, self.stdout, nil },
  }, function() end)
  assert(self.proc, 'could not start the embedded Neovim')

  self.stdout:read_start(function(err, data)
    assert(not err, err)
    if data then
      self:_feed(data)
    end
  end)

  self:request('nvim_ui_attach', width, height, { ext_linegrid = true })
  self:settle()
  return self
end

---@param data string
function Session:_feed(data)
  self.buffer = self.buffer .. data
  local pos = 1
  while pos <= #self.buffer do
    local ok, obj, next_pos = pcall(self.unpacker, self.buffer, pos)
    if not ok or obj == nil then
      break
    end
    pos = next_pos
    if obj[1] == 1 then
      self.responses[obj[2]] = { err = obj[3], result = obj[4] }
    elseif obj[1] == 2 and obj[2] == 'redraw' then
      self:_redraw(obj[3])
    end
  end
  self.buffer = self.buffer:sub(pos)
end

---@param events table[]
function Session:_redraw(events)
  for _, event in ipairs(events) do
    local name = event[1]
    for i = 2, #event do
      local args = event[i]
      if name == 'grid_line' and args[1] == 1 then
        local row, col = args[2] + 1, args[3] + 1
        for _, cell in ipairs(args[4]) do
          for _ = 1, cell[3] or 1 do
            if self.grid[row] and col <= self.width then
              self.grid[row][col] = cell[1]
            end
            col = col + 1
          end
        end
      elseif name == 'grid_scroll' and args[1] == 1 then
        local top, bot, left, right, rows = args[2] + 1, args[3], args[4] + 1, args[5], args[6]
        local copy = vim.deepcopy(self.grid)
        for row = top, bot do
          local src = row + rows
          if src >= top and src <= bot then
            for col = left, right do
              self.grid[row][col] = copy[src][col]
            end
          end
        end
      elseif name == 'flush' then
        local lines = {}
        for row = 1, self.height do
          lines[row] = table.concat(self.grid[row])
        end
        table.insert(self.frames, table.concat(lines, '\n'))
      end
    end
  end
end

---@param method string
---@param ... any
---@return any
function Session:request(method, ...)
  self.msgid = self.msgid + 1
  local id = self.msgid
  self.stdin:write(vim.mpack.encode({ 0, id, method, { ... } }))
  local got = vim.wait(5000, function()
    return self.responses[id] ~= nil
  end, 5)
  assert(got, method .. ' timed out')
  local response = self.responses[id]
  assert(
    response.err == vim.NIL or response.err == nil,
    method .. ': ' .. vim.inspect(response.err)
  )
  return response.result
end

---Let the child draw. Frames only arrive while this loop runs.
---@param ms number|nil
function Session:settle(ms)
  vim.wait(ms or 60, function()
    return false
  end, 5)
end

---Type keys one at a time, the way a person does.
---@param keys string
---@param delay number|nil milliseconds between keys
function Session:type(keys, delay)
  for char in keys:gmatch('.') do
    self:request('nvim_input', char)
    self:settle(delay or 15)
  end
end

---@param keys string
function Session:feed(keys)
  self:request('nvim_input', keys)
  self:settle()
end

---Frames drawn since the marker returned by mark().
---@return number
function Session:mark()
  return #self.frames
end

---How many frames since `from` contain `text` anywhere on screen.
---@param text string
---@param from number|nil
---@return number
function Session:frames_with(text, from)
  local count = 0
  for i = (from or 0) + 1, #self.frames do
    if self.frames[i]:find(text, 1, true) then
      count = count + 1
    end
  end
  return count
end

---Wait until `text` is on screen, so a test never races the first redraw.
---@param text string
---@param ms number|nil
---@return boolean
function Session:wait_for(text, ms)
  return vim.wait(ms or 2000, function()
    return self:screen():find(text, 1, true) ~= nil
  end, 10)
end

---@return string
function Session:screen()
  return self.frames[#self.frames] or ''
end

function Session:stop()
  -- No `qa!` request: the child exits without answering it, and waiting for
  -- that answer is five seconds per session.
  pcall(function()
    self.stdout:read_stop()
  end)
  if self.proc and not self.proc:is_closing() then
    pcall(function()
      self.proc:kill('sigkill')
    end)
  end
  for _, pipe in ipairs({ self.stdin, self.stdout }) do
    if pipe and not pipe:is_closing() then
      pcall(function()
        pipe:close()
      end)
    end
  end
  vim.fn.delete(self.dir, 'rf')
end

return M
