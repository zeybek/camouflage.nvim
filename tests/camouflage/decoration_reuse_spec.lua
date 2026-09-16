-- Work that decoration passes skip when nothing changed: re-entering a buffer,
-- the root lookup of an inactive policy, and follow-cursor line moves.
describe('camouflage decoration reuse', function()
  local core
  local state
  local config
  local buffers = {}
  local calls
  local original_apply

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

  local function enter(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
  end

  local function mark_count(bufnr)
    return #vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, 0, -1, { details = true })
  end

  before_each(function()
    clear_camouflage_modules()
    require('camouflage').setup({
      project_config = { enabled = false, watch_enabled = false },
      reveal = { notify = false },
    })
    core = require('camouflage.core')
    state = require('camouflage.state')
    config = require('camouflage.config')
    calls = 0
    original_apply = core.apply_decorations
    core.apply_decorations = function(...)
      calls = calls + 1
      return original_apply(...)
    end
  end)

  after_each(function()
    local reveal = require('camouflage.reveal')
    if reveal.is_follow_cursor_enabled() then
      reveal.stop_follow_cursor()
    end
    core.apply_decorations = original_apply
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    buffers = {}
  end)

  describe('entering a buffer', function()
    local env_buf
    local other_buf

    before_each(function()
      env_buf = new_buffer('reuse.env', { 'API_KEY=reuse-secret' })
      other_buf = new_buffer('other.env', { 'OTHER=value' })
      enter(env_buf)
      enter(other_buf)
      calls = 0
    end)

    it('does not decorate again when nothing changed', function()
      enter(env_buf)
      enter(other_buf)
      enter(env_buf)

      assert.equals(0, calls)
      assert.equals(1, mark_count(env_buf))
    end)

    it('decorates again after the text changed', function()
      vim.api.nvim_buf_set_lines(env_buf, 0, -1, false, { 'API_KEY=changed-secret' })
      enter(env_buf)

      assert.equals(1, calls)
    end)

    it('decorates again after a buffer-local override changed', function()
      vim.b[env_buf].camouflage_mask_char = '#'
      enter(env_buf)

      assert.equals(1, calls)
    end)

    it('decorates again after config, hooks, checks or parsers changed', function()
      local changes = {
        function()
          config.set('mask_char', '+')
        end,
        function()
          require('camouflage').on('variable_detected', function() end)
        end,
        function()
          require('camouflage').register_check({ name = 'reuse_probe', run = function() end })
        end,
        function()
          require('camouflage.parsers').clear_cache()
        end,
      }
      for i, change in ipairs(changes) do
        change()
        enter(env_buf)
        assert.equals(i, calls, 'change ' .. i .. ' did not trigger a pass')
        enter(other_buf)
        calls = i
      end
      require('camouflage').unregister_check('reuse_probe')
    end)

    it('still turns wrap off in a new window that shows the buffer', function()
      vim.cmd('split')
      local win = vim.api.nvim_get_current_win()
      vim.wo[win].wrap = true
      vim.api.nvim_win_set_buf(win, other_buf)
      enter(env_buf)

      assert.equals(0, calls)
      assert.is_false(vim.wo[win].wrap)
      vim.cmd('close')
    end)
  end)

  describe('inactive policy', function()
    it('does not search for the project root', function()
      local policy = require('camouflage.policy')
      local searches = 0
      local original_resolve = policy.resolve_root
      policy.resolve_root = function(...)
        searches = searches + 1
        return original_resolve(...)
      end

      local bufnr = new_buffer('policy.env', { 'TOKEN=policy-secret' })
      original_apply(bufnr)
      local inactive_searches = searches

      config.set('policy.rules', { { id = 'r', action = 'ignore', key = '^NOPE$' } })
      original_apply(bufnr)
      policy.resolve_root = original_resolve

      assert.equals(0, inactive_searches)
      assert.equals(1, searches)
    end)
  end)

  describe('follow cursor', function()
    local function line_masked(bufnr, row)
      for _, mark in
        ipairs(vim.api.nvim_buf_get_extmarks(bufnr, state.namespace, { row, 0 }, { row, -1 }, {
          details = true,
        }))
      do
        if mark[4].virt_text then
          return true
        end
      end
      return false
    end

    it('moves the reveal between lines without decorating the buffer again', function()
      local lines = {}
      for i = 1, 20 do
        lines[i] = string.format('KEY_%d=follow-secret-%d', i, i)
      end
      local bufnr = new_buffer('follow.env', lines)
      enter(bufnr)
      local reveal = require('camouflage.reveal')
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.start_follow_cursor()
      calls = 0

      for row = 2, 10 do
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        vim.cmd('doautocmd CursorMoved')
        assert.is_false(line_masked(bufnr, row - 1), 'current line should be revealed')
        assert.is_true(line_masked(bufnr, row - 2), 'previous line should be masked again')
      end

      assert.equals(0, calls)
    end)

    it('decorates the buffer again when the text changed while revealed', function()
      local bufnr = new_buffer('follow-edit.env', { 'A=first-secret', 'B=second-secret' })
      enter(bufnr)
      local reveal = require('camouflage.reveal')
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      reveal.start_follow_cursor()
      -- Edit inside the revealed line (replacing the whole line would move the
      -- reveal anchor to the next line).
      vim.api.nvim_buf_set_text(bufnr, 0, 2, 0, 7, { 'edited' })
      calls = 0

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.cmd('doautocmd CursorMoved')

      assert.equals(1, calls)
      assert.is_true(line_masked(bufnr, 0))
    end)
  end)
end)
