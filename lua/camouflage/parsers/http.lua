---@mod camouflage.parsers.http HTTP parser
---@brief [[
--- Parser for .http files (REST client format).
--- Masks variable declarations (@variable_name = value) and, in each request,
--- sensitive query parameters, sensitive header values and a JSON body.
--- Reference: https://neovim.getkulala.net/docs/usage/http-file-spec/
---@brief ]]

local M = {}

local util = require('camouflage.parsers.util')

---@param content string
---@param bufnr number|nil Buffer number for TreeSitter parsing
---@return ParsedVariable[]
function M.parse(content, bufnr)
  local variables
  -- Try TreeSitter first if buffer is provided
  if bufnr then
    local ts = require('camouflage.treesitter')
    variables = ts.parse(bufnr, 'http', content)
  end
  -- Fallback to regex-based parsing
  variables = variables or M.parse_regex(content)

  -- Requests are read line by line either way: the tree-sitter query only
  -- covers variable declarations.
  local seen = {}
  for _, var in ipairs(variables) do
    seen[var.start_index] = true
  end
  for _, var in ipairs(M.parse_requests(content)) do
    if not seen[var.start_index] then
      table.insert(variables, var)
    end
  end
  table.sort(variables, function(a, b)
    return a.start_index < b.start_index
  end)
  return variables
end

local METHODS = {
  GET = true,
  POST = true,
  PUT = true,
  PATCH = true,
  DELETE = true,
  HEAD = true,
  OPTIONS = true,
  CONNECT = true,
  TRACE = true,
}

-- Words in a header or parameter name that mark its value as a credential.
-- Content-Type, Accept, page and the like stay readable.
local SENSITIVE_NAME_PARTS = {
  'auth',
  'token',
  'key',
  'secret',
  'password',
  'passwd',
  'cookie',
  'session',
  'signature',
  'credential',
}

---@param name string
---@return boolean
function M.is_sensitive_name(name)
  local lowered = name:lower()
  for _, part in ipairs(SENSITIVE_NAME_PARTS) do
    if lowered:find(part, 1, true) then
      return true
    end
  end
  return false
end

---A `{{variable}}` reference only, which says nothing secret by itself.
---@param value string
---@return boolean
local function is_reference(value)
  return value:match('^{{[^}]*}}$') ~= nil
end

---@param out ParsedVariable[]
---@param key string
---@param value string
---@param start_index number 0-based
---@param line_num number 1-based
local function add(out, key, value, start_index, line_num)
  if value == '' or value:match('^%s*$') or is_reference(value) then
    return
  end
  table.insert(out, {
    key = key,
    value = value,
    start_index = start_index,
    end_index = start_index + #value,
    line_number = line_num - 1,
    is_nested = true,
    is_commented = false,
  })
end

---`name=value&name=value`, as in a query string or a form body. Only the
---values of sensitive names are reported.
---@param text string
---@param text_start number 0-based offset of `text`
---@param prefix string
---@param line_num number
---@param out ParsedVariable[]
local function read_params(text, text_start, prefix, line_num, out)
  for name, value_pos, value in text:gmatch('([^&=%s#]+)=()([^&%s#]*)') do
    if M.is_sensitive_name(name) then
      add(out, prefix .. name, value, text_start + value_pos - 1, line_num)
    end
  end
end

---A header value. `Authorization: Bearer x` keeps the scheme visible, and a
---cookie header keeps its cookie names.
---@param name string
---@param value string
---@param value_start number 0-based
---@param line_num number
---@param out ParsedVariable[]
local function read_header(name, value, value_start, line_num, out)
  local key = 'header.' .. name
  local lowered = name:lower()
  if lowered == 'cookie' or lowered == 'set-cookie' then
    for pos, cookie, cookie_value in value:gmatch('()([^;=%s]+)=([^;]*)') do
      local offset = pos + #cookie -- the `=` sits right after the name
      add(out, key .. '.' .. cookie, cookie_value, value_start + offset, line_num)
    end
    return
  end
  local scheme, credential_pos = value:match('^(%a+)%s+()%S')
  if scheme and (lowered:find('auth', 1, true)) then
    add(out, key, value:sub(credential_pos), value_start + credential_pos - 1, line_num)
    return
  end
  add(out, key, value, value_start, line_num)
end

---A JSON body, through the JSON parser, with its offsets moved to the file.
---@param body string
---@param body_start number 0-based
---@param offsets number[] Line start offsets of the whole content
---@param out ParsedVariable[]
local function read_body(body, body_start, offsets, out)
  local first = body:match('^%s*(.)')
  if first ~= '{' and first ~= '[' then
    if body:match('^%s*[%w_%.%-]+=') then
      local lead = #body:match('^%s*')
      local row = util.row_of(offsets, body_start + lead)
      read_params(body:sub(lead + 1):match('^[^\n]*'), body_start + lead, 'body.', row + 1, out)
    end
    return
  end
  local ok, parsed = pcall(require('camouflage.parsers.json').parse_regex, body)
  if not ok or type(parsed) ~= 'table' then
    return
  end
  for _, var in ipairs(parsed) do
    local value = var.value or ''
    if value ~= '' and not is_reference(value) then
      local start_index = body_start + var.start_index
      table.insert(out, {
        key = 'body.' .. var.key,
        value = value,
        start_index = start_index,
        end_index = body_start + var.end_index,
        line_number = util.row_of(offsets, start_index),
        is_nested = true,
        is_commented = false,
        is_multiline = var.is_multiline,
      })
    end
  end
end

---@param line string
---@return boolean
function M.is_comment_or_variable(line)
  return line:match('^%s*#') ~= nil or line:match('^%s*//') ~= nil or line:match('^%s*@') ~= nil
end

---Query parameters, headers and the JSON body of every request in the file.
---@param content string
---@return ParsedVariable[]
function M.parse_requests(content)
  local out = {}
  local lines = vim.split(content, '\n', { plain = true })
  local offsets = require('camouflage.offsets').from_content(content)
  local mode = 'idle' -- idle -> headers -> body
  local body_lines, body_start = {}, nil

  local function flush_body()
    if body_start and #body_lines > 0 then
      read_body(table.concat(body_lines, '\n'), body_start, offsets, out)
    end
    body_lines, body_start = {}, nil
  end

  local index = 0
  for line_num, line in ipairs(lines) do
    local line_start = index
    index = index + #line + 1

    if line:match('^%s*###') then
      flush_body()
      mode = 'idle'
    elseif mode == 'body' then
      -- `> {% script %}` and `<> response` lines end the body
      if line:match('^%s*[<>]') then
        flush_body()
        mode = 'idle'
      else
        body_start = body_start or line_start
        table.insert(body_lines, line)
      end
    elseif mode == 'idle' and not M.is_comment_or_variable(line) then
      local method, target_pos = line:match('^%s*(%u+)%s+()%S')
      local url_pos = line:match('^%s*()https?://')
      if (method and METHODS[method]) or url_pos then
        local target_start = url_pos or target_pos
        local target = line:sub(target_start):match('^%S+')
        local query_pos = target:find('?', 1, true)
        if query_pos then
          local query_start = target_start + query_pos -- 1-based position after `?`
          read_params(
            target:sub(query_pos + 1),
            line_start + query_start - 1,
            'query.',
            line_num,
            out
          )
        end
        mode = 'headers'
      end
    elseif mode == 'headers' and not M.is_comment_or_variable(line) then
      if line:match('^%s*$') then
        mode = 'body'
      else
        local name, value_pos = line:match('^%s*([%w_%-]+)%s*:%s*()')
        if name and M.is_sensitive_name(name) then
          local value = line:sub(value_pos):match('^(.-)%s*$')
          read_header(name, value, line_start + value_pos - 1, line_num, out)
        end
      end
    end
  end
  flush_body()
  return out
end

---@param content string
---@return ParsedVariable[]
function M.parse_regex(content)
  local variables = {}
  local lines = vim.split(content, '\n', { plain = true })
  local current_index = 0

  for line_num, line in ipairs(lines) do
    local result = M.parse_line(line, line_num, current_index)
    if result then
      table.insert(variables, result)
    end
    current_index = current_index + #line + 1
  end

  return variables
end

---Parse a single line for variable declaration
---@param line string
---@param line_num number 1-indexed line number
---@param current_index number Byte offset where line starts
---@return ParsedVariable|nil
function M.parse_line(line, line_num, current_index)
  -- Pattern: @variable_name = value
  -- Variable names can contain letters, numbers, underscores, dots, hyphens, and $
  local key, value = line:match('^%s*@([A-Za-z_%.%$][A-Za-z0-9_%.%-%$]*)%s*=%s*(.+)$')

  if not key or not value then
    return nil
  end

  -- Trim trailing whitespace from value
  value = value:match('^(.-)%s*$')

  if not value or #value == 0 then
    return nil
  end

  -- Calculate value position
  local at_pos = line:find('@')
  local eq_pos = line:find('=', at_pos)
  if not eq_pos then
    return nil
  end

  local after_eq = line:sub(eq_pos + 1)
  local whitespace_before = #after_eq - #after_eq:gsub('^%s*', '')
  local value_start = current_index + eq_pos + whitespace_before
  local value_end = value_start + #value

  return {
    key = key,
    value = value,
    start_index = value_start,
    end_index = value_end,
    line_number = line_num - 1, -- 0-indexed
    is_nested = false,
    is_commented = false,
  }
end

M.filetypes = { 'http' }
M.file_patterns = { '*.http' }
M.treesitter = { lang = 'http' }

return M
