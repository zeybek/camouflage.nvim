---@mod camouflage.commands User commands

local M = {}

---Setup all user commands for camouflage
---@return nil
function M.setup()
  vim.api.nvim_create_user_command('CamouflageToggle', function()
    local camouflage = require('camouflage')
    local was_enabled = camouflage.is_enabled()
    camouflage.toggle()
    -- Presentation mode refuses to turn masking off, and says so itself.
    if camouflage.is_enabled() ~= was_enabled then
      local status = camouflage.is_enabled() and 'enabled' or 'disabled'
      vim.notify('[camouflage] ' .. status, vim.log.levels.INFO)
    end
  end, { desc = 'Toggle Camouflage' })

  vim.api.nvim_create_user_command('CamouflageParsers', function()
    local entries = require('camouflage.parsers').list()
    if #entries == 0 then
      vim.notify('[camouflage] No parsers registered', vim.log.levels.INFO)
      return
    end
    local lines = { '[camouflage] Registered parsers:' }
    for _, e in ipairs(entries) do
      local fts = e.filetypes and table.concat(e.filetypes, ',') or '-'
      local pats = e.file_patterns and table.concat(e.file_patterns, ',') or '-'
      table.insert(
        lines,
        string.format(
          '  %-14s priority=%-3d source=%-7s filetypes=%s patterns=%s',
          e.name,
          e.priority or 50,
          e.source or '-',
          fts,
          pats
        )
      )
    end
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  end, { desc = 'List registered camouflage parsers' })

  vim.api.nvim_create_user_command('CamouflageExpiryToggle', function()
    local cfg = require('camouflage.config')
    local current = (cfg.get().checks or {}).expiry or {}
    local new_enabled = current.enabled == false
    cfg.set('checks.expiry.enabled', new_enabled)
    local expiry = require('camouflage.checks.expiry')
    if new_enabled then
      expiry.setup()
      -- Re-decorate all loaded supported buffers immediately so badges
      -- appear without waiting for the next edit/BufEnter.
      vim.schedule(function()
        require('camouflage.autocmds').apply_to_loaded_buffers()
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_valid(bufnr) then
          pcall(expiry.start_auto_refresh, bufnr)
        end
      end)
      vim.notify('[camouflage] expiry check enabled', vim.log.levels.INFO)
    else
      expiry.teardown()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        require('camouflage.checks').clear_check(b, 'expiry')
      end
      vim.notify('[camouflage] expiry check disabled', vim.log.levels.INFO)
    end
  end, { desc = 'Toggle JWT expiry check on/off' })

  vim.api.nvim_create_user_command('CamouflageWeakSecretToggle', function()
    local cfg = require('camouflage.config')
    local current = cfg.get_check('weak_secret')
    local new_enabled = current.enabled == false
    cfg.set('checks.weak_secret.enabled', new_enabled)
    local weak_secret = require('camouflage.checks.weak_secret')
    if new_enabled then
      weak_secret.setup()
      vim.schedule(function()
        require('camouflage.autocmds').apply_to_loaded_buffers()
      end)
      vim.notify('[camouflage] weak secret check enabled', vim.log.levels.INFO)
    else
      weak_secret.teardown()
      weak_secret.clear_all()
      vim.notify('[camouflage] weak secret check disabled', vim.log.levels.INFO)
    end
  end, { desc = 'Toggle weak secret check on/off' })

  vim.api.nvim_create_user_command('CamouflageRefresh', function()
    require('camouflage').refresh()
    vim.notify('[camouflage] refreshed', vim.log.levels.INFO)
  end, { desc = 'Refresh Camouflage decorations' })

  vim.api.nvim_create_user_command('CamouflageAudit', function(opts)
    local audit = require('camouflage.audit')
    local cfg = require('camouflage.config').get().audit or {}
    local destination = opts.bang and 'loclist' or (cfg.destination or 'quickfix')

    -- `--json=<path>` writes the report, `-` writes it to stdout. `--quit`
    -- leaves with 1 when anything was found, which is what a CI step reads.
    local json_path, quit, path_args = nil, false, {}
    for _, arg in ipairs(opts.fargs) do
      local json = arg:match('^%-%-json=(.+)$')
      if json then
        json_path = json
      elseif arg == '--json' then
        json_path = '-'
      elseif arg == '--quit' then
        quit = true
      else
        table.insert(path_args, arg)
      end
    end

    audit.run({
      path = path_args[1],
      async = true,
      destination = destination,
      on_complete = function(result)
        if json_path then
          local ok, err = audit.write_report(result, json_path)
          if not ok then
            vim.notify(
              string.format('[camouflage] could not write %s: %s', json_path, tostring(err)),
              vim.log.levels.ERROR
            )
          end
          if quit then
            vim.cmd(('cquit %d'):format(#result.findings > 0 and 1 or 0))
            return
          end
        elseif quit then
          vim.cmd(('cquit %d'):format(#result.findings > 0 and 1 or 0))
          return
        end

        audit.set_list(result, {
          destination = destination,
          open = cfg.open ~= false,
        })

        if cfg.notify ~= false then
          if #result.findings == 0 then
            vim.notify('[camouflage] audit found no masked values', vim.log.levels.INFO)
          else
            local suffix = #result.errors > 0 and string.format(' (%d errors)', #result.errors)
              or ''
            vim.notify(
              string.format('[camouflage] audit found %d masked values%s', #result.findings, suffix),
              vim.log.levels.INFO
            )
          end
        end
      end,
    })
  end, {
    desc = 'Audit workspace for masked values',
    bang = true,
    nargs = '*',
    complete = 'file',
  })

  vim.api.nvim_create_user_command('CamouflageStatus', function()
    local camouflage = require('camouflage')
    local state = require('camouflage.state')
    local parsers = require('camouflage.parsers')
    local cfg = require('camouflage.config').get()

    local enabled = camouflage.is_enabled()
    local bufnr = vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local _, parser_name = parsers.find_parser_for_file(filename)
    local vars = state.get_variables(bufnr)
    local policy_cfg = cfg.policy or {}
    local policy_stats = state.get_policy_stats(bufnr) or {}

    local lines = {
      '[camouflage] Status:',
      '  Global: ' .. (enabled and 'enabled' or 'disabled'),
      '  Buffer: ' .. (state.is_buffer_masked(bufnr) and 'masked' or 'not masked'),
      '  Parser: ' .. (parser_name or 'none'),
      '  Masked values: ' .. #vars,
      '  Policy: ' .. (policy_cfg.enabled == false and 'disabled' or 'enabled'),
      '  Policy ignored: ' .. tostring(policy_stats.ignored or 0),
      '  Presentation mode: ' .. require('camouflage.present').status(),
    }
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  end, { desc = 'Show Camouflage status' })

  vim.api.nvim_create_user_command('CamouflageYank', function(opts)
    local yank = require('camouflage.yank')
    yank.yank({
      force_picker = opts.bang,
      register = opts.args ~= '' and opts.args or nil,
    })
  end, {
    desc = 'Copy unmasked value to clipboard',
    bang = true,
    nargs = '?',
  })

  vim.api.nvim_create_user_command('CamouflageRegisters', function()
    require('camouflage.registers').show()
  end, { desc = 'List registers with masked values redacted' })

  vim.api.nvim_create_user_command('CamouflagePresent', function(opts)
    local present = require('camouflage.present')
    if opts.bang then
      if present.stop() then
        vim.notify('[camouflage] presentation mode off', vim.log.levels.INFO)
      end
      return
    end
    if present.start() then
      vim.notify('[camouflage] presentation mode on', vim.log.levels.INFO)
    else
      vim.notify('[camouflage] presentation mode is already on', vim.log.levels.INFO)
    end
  end, {
    desc = 'Mask everything for a demo (! to leave)',
    bang = true,
  })

  vim.api.nvim_create_user_command('CamouflageShield', function()
    require('camouflage.shield').open()
  end, { desc = 'Cover the whole editor until a key is pressed' })

  vim.api.nvim_create_user_command('CamouflageShieldPassword', function(opts)
    local shield = require('camouflage.shield')
    if opts.bang then
      if shield.remove_password() then
        vim.notify('[camouflage] shield password removed', vim.log.levels.INFO)
      else
        vim.notify('[camouflage] no shield password was set', vim.log.levels.INFO)
      end
      return
    end
    local hash = shield.prompt_password()
    if not hash then
      return
    end
    local ok, err = shield.save_password(hash)
    if ok then
      vim.notify('[camouflage] shield password set', vim.log.levels.INFO)
    else
      vim.notify(
        '[camouflage] could not save the password: ' .. tostring(err),
        vim.log.levels.ERROR
      )
    end
  end, { desc = 'Set the shield password (! to remove it)', bang = true })

  vim.api.nvim_create_user_command('CamouflageReveal', function(opts)
    local reveal = require('camouflage.reveal')
    if opts.bang then
      reveal.hide()
    else
      reveal.toggle()
    end
  end, {
    desc = 'Reveal masked values on current line',
    bang = true,
  })

  vim.api.nvim_create_user_command('CamouflageFollowCursor', function(opts)
    local reveal = require('camouflage.reveal')
    reveal.toggle_follow_cursor({
      force_disable = opts.bang,
    })
  end, {
    desc = 'Toggle follow cursor mode (auto-reveal current line)',
    bang = true,
  })

  -- Pwned password check commands
  vim.api.nvim_create_user_command('CamouflagePwnedCheck', function()
    require('camouflage.pwned').check_current()
  end, { desc = 'Check if value under cursor is pwned' })

  vim.api.nvim_create_user_command('CamouflagePwnedCheckLine', function()
    require('camouflage.pwned').check_line()
  end, { desc = 'Check all values on current line' })

  vim.api.nvim_create_user_command('CamouflagePwnedCheckBuffer', function()
    require('camouflage.pwned').check_buffer()
  end, { desc = 'Check all values in buffer' })

  vim.api.nvim_create_user_command('CamouflagePwnedClear', function()
    require('camouflage.pwned').clear()
  end, { desc = 'Clear pwned indicators from buffer' })

  vim.api.nvim_create_user_command('CamouflagePwnedClearCache', function()
    require('camouflage.pwned').clear_cache()
  end, { desc = 'Clear pwned check cache' })

  vim.api.nvim_create_user_command('CamouflageProjectConfigStatus', function()
    local status = require('camouflage').project_config_status()
    local lines = {
      '[camouflage] Project Config Status:',
      '  Loaded: ' .. (status.loaded and 'yes' or 'no'),
      '  Path: ' .. (status.path or 'none'),
      '  Errors: ' .. #status.errors,
    }
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  end, { desc = 'Show Camouflage project config status' })

  vim.api.nvim_create_user_command('CamouflageProjectConfigWatchStatus', function()
    local status = require('camouflage').project_config_watch_status()
    local lines = {
      '[camouflage] Project Config Watch Status:',
      '  Enabled: ' .. (status.enabled and 'yes' or 'no'),
      '  Backend: ' .. status.backend,
      '  Watched roots: ' .. status.root_count,
      '  Last event: ' .. (status.last_event_at and tostring(status.last_event_at) or 'none'),
    }
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  end, { desc = 'Show Camouflage project config watcher status' })

  vim.api.nvim_create_user_command('CamouflageInit', function(opts)
    require('camouflage.init_command').init({ force = opts.bang })
  end, { desc = 'Create .camouflage.yaml in project root', bang = true })
end

return M
