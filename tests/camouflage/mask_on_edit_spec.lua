-- Edits are masked while they are applied, before the debounced decoration pass
-- runs. Every assertion here runs synchronously after the edit, with no event
-- loop tick in between, which is what a redraw would see.
describe('camouflage masks edits before redraw', function()
  local core
  local config
  local buffers = {}

  local function clear_camouflage_modules()
    for name, _ in pairs(package.loaded) do
      if name:match('^camouflage') then
        package.loaded[name] = nil
      end
    end
  end

  local function new_buffer(name, lines)
    local bufnr = vim.api.nvim_create_buf(true, false)
    table.insert(buffers, bufnr)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '/' .. name)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
  end

  -- Open a buffer the way BufEnter does: tracked, then decorated.
  local function open(name, lines)
    local bufnr = new_buffer(name, lines)
    vim.api.nvim_set_current_buf(bufnr)
    require('camouflage.state').init_buffer(bufnr)
    core.apply_decorations(bufnr)
    return bufnr
  end

  -- Masking extmarks from any namespace that cover [col, col + len) on row.
  local function covered(bufnr, row, col, len)
    for _, ns in pairs(vim.api.nvim_get_namespaces()) do
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { row, 0 }, { row, -1 }, {
        details = true,
      })
      for _, mark in ipairs(marks) do
        local details = mark[4]
        if details.virt_text and details.virt_text_pos == 'overlay' then
          local start_col = mark[3]
          local end_col = details.end_col or start_col
          if start_col <= col and end_col >= col + len then
            return true
          end
        end
      end
    end
    return false
  end

  local function col_of(bufnr, row, text)
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    local s = line:find(text, 1, true)
    assert(s, ('"%s" not found on row %d: %s'):format(text, row, line))
    return s - 1
  end

  local function assert_masked(bufnr, row, text)
    assert.is_true(
      covered(bufnr, row, col_of(bufnr, row, text), #text),
      ('"%s" on row %d is not masked'):format(text, row)
    )
  end

  local function assert_not_masked(bufnr, row, text)
    assert.is_false(
      covered(bufnr, row, col_of(bufnr, row, text), #text),
      ('"%s" on row %d should not be masked'):format(text, row)
    )
  end

  before_each(function()
    clear_camouflage_modules()
    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
    })
    core = require('camouflage.core')
    config = require('camouflage.config')
  end)

  after_each(function()
    local reveal = require('camouflage.reveal')
    if reveal.is_revealed() then
      reveal.hide()
    end
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
  end)

  it('masks a line added to a .env', function()
    local bufnr = open('added.env', { 'API_KEY=already-masked' })
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { 'NEW_TOKEN=typed-secret' })
    assert_masked(bufnr, 1, 'typed-secret')
  end)

  it('masks every line of a multi-line paste', function()
    local bufnr = open('paste.env', { 'API_KEY=already-masked' })
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, {
      'PASTE_ONE=first-pasted-secret',
      'export PASTE_TWO="second-pasted-secret"',
    })
    assert_masked(bufnr, 1, 'first-pasted-secret')
    assert_masked(bufnr, 2, 'second-pasted-secret')
  end)

  it('masks characters appended to an already masked value', function()
    local bufnr = open('append.env', { 'API_KEY=already-masked' })
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    vim.api.nvim_buf_set_text(bufnr, 0, #line, 0, #line, { '-and-more' })
    assert_masked(bufnr, 0, 'already-masked-and-more')
  end)

  it('masks the first value typed into a buffer that had none', function()
    local bufnr = open('empty.env', { '# nothing here yet' })
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { 'FIRST=first-secret' })
    assert_masked(bufnr, 1, 'first-secret')
  end)

  it('masks values typed into other formats', function()
    local json = open('typed.json', { '{', '  "name": "app"', '}' })
    vim.api.nvim_buf_set_lines(json, 2, 2, false, { '  "token": "json-secret",' })
    assert_masked(json, 2, 'json-secret')

    local yaml = open('typed.yaml', { 'name: app' })
    vim.api.nvim_buf_set_lines(yaml, 1, 1, false, { '- password: yaml-secret' })
    assert_masked(yaml, 1, 'yaml-secret')

    local xml = open('typed.xml', { '<config>', '</config>' })
    vim.api.nvim_buf_set_lines(xml, 1, 1, false, { '  <password>xml-secret</password>' })
    assert_masked(xml, 1, 'xml-secret')

    local docker = open('Dockerfile', { 'FROM alpine' })
    vim.api.nvim_buf_set_lines(docker, 1, 1, false, { 'ENV API_TOKEN docker-secret' })
    assert_masked(docker, 1, 'docker-secret')
  end)

  it('leaves the pass to replace the provisional masks', function()
    local bufnr = open('replace.env', { 'API_KEY=already-masked' })
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { 'NEW_TOKEN=typed-secret' })
    core.apply_decorations(bufnr)

    local guard_marks =
      vim.api.nvim_buf_get_extmarks(bufnr, require('camouflage.guard').namespace, 0, -1, {})
    assert.equals(0, #guard_marks)
    assert_masked(bufnr, 1, 'typed-secret')
  end)

  it('does not mask a line the user revealed', function()
    local bufnr = open('revealed.env', { 'API_KEY=already-masked', 'OTHER=other-secret' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    require('camouflage.reveal').reveal_line()
    assert_not_masked(bufnr, 0, 'already-masked')

    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    vim.api.nvim_buf_set_text(bufnr, 0, #line, 0, #line, { 'X' })
    assert_not_masked(bufnr, 0, 'already-maskedX')
  end)

  it('does not mask edits when masking is turned off', function()
    local bufnr = open('disabled.env', { 'API_KEY=already-masked' })
    config.set('enabled', false)
    core.apply_decorations(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { 'NEW_TOKEN=typed-secret' })
    assert_not_masked(bufnr, 1, 'typed-secret')
    config.set('enabled', true)
  end)

  it('does not mask edits in a picker preview buffer', function()
    -- Preview buffers are reused for whatever file is selected next.
    local bufnr = new_buffer('preview.env', { 'API_KEY=preview-secret' })
    require('camouflage.state').init_buffer(bufnr)
    core.apply_decorations(bufnr, 'preview.env')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'retries = 42' })
    assert_not_masked(bufnr, 0, '42')
    assert.is_false(require('camouflage.guard').is_attached(bufnr))
  end)

  it('stops masking edits once the buffer is no longer tracked', function()
    local bufnr = open('untracked.env', { 'API_KEY=already-masked' })
    require('camouflage.state').remove_buffer(bufnr)
    core.clear_decorations(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { 'NEW_TOKEN=typed-secret' })
    assert_not_masked(bufnr, 1, 'typed-secret')
    assert.is_false(require('camouflage.guard').is_attached(bufnr))
  end)
end)
