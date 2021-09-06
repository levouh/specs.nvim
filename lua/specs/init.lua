local specs = {}
local opts = {}
local module = { active = {} }

local old_cur
local au_toggle

local function end_repeat(timer, winid)
  if timer then
    pcall(vim.loop.close, timer)
  end

  pcall(vim.api.nvim_win_close, winid, true)

  module.active[winid] = nil
end

local function should_show_specs(start_winid)
  if not vim.api.nvim_win_is_valid(start_winid) then
    return false
  end

  if type(opts.ignore_filetypes) ~= "table" or type(opts.ignore_buftypes) ~= "table" then
    return true
  end

  local buftype, filetype, ok
  ok, buftype = pcall(vim.api.nvim_buf_get_option, 0, "buftype")
  if ok and opts.ignore_buftypes[buftype] then
    return false
  end

  ok, filetype = pcall(vim.api.nvim_buf_get_option, 0, "filetype")
  if ok and opts.ignore_filetypes[filetype] then
    return false
  end

  return true
end

function specs.close_active()
  for winid, _ in pairs(module.active) do
    end_repeat(nil, winid)
  end
end

function specs.on_cursor_moved()
  local cur = vim.api.nvim_win_get_cursor(0)

  if old_cur then
    local jump = math.abs(cur[1] - old_cur[1])

    if jump >= opts.min_jump then
      specs.show_specs()
    end
  end

  old_cur = cur
end

function specs.show_specs()
  local start_winid = vim.api.nvim_get_current_win()

  if not should_show_specs(start_winid) then
    return
  end

  local cursor_col = vim.fn.wincol() - 1
  local cursor_row = vim.fn.winline() - 1
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(bufnr, false, {
    relative = "win",
    width = 1,
    height = 1,
    col = cursor_col,
    row = cursor_row,
    style = "minimal",
  })

  module.active[winid] = { winid = winid, bufnr = bufnr }
  vim.api.nvim_win_set_option(winid, "winhl", "Normal:" .. opts.popup.winhl)
  vim.api.nvim_win_set_option(winid, "winblend", opts.popup.blend)

  local cnt = 0
  local config = vim.api.nvim_win_get_config(winid)
  local timer = vim.loop.new_timer()
  local closed = false

  vim.loop.timer_start(
    timer,
    opts.popup.delay_ms,
    opts.popup.inc_ms,
    vim.schedule_wrap(function()
      if closed or vim.api.nvim_get_current_win() ~= start_winid then
        if not closed then
          end_repeat(timer, winid)

          -- Callbacks might stack up before the timer actually gets closed, track that state
          -- internally here instead
          closed = true
        end

        return
      end

      if vim.api.nvim_win_is_valid(winid) then
        local bl = opts.popup.fader(opts.popup.blend, cnt)
        local dm = opts.popup.resizer(opts.popup.width, cursor_col, cnt)

        if bl ~= nil then
          vim.api.nvim_win_set_option(winid, "winblend", bl)
        end

        if dm ~= nil then
          config["col"][false] = dm[2]
          vim.api.nvim_win_set_config(winid, config)
          vim.api.nvim_win_set_width(winid, dm[1])
        end

        if bl == nil and dm == nil then -- Done blending and resizing
          end_repeat(timer, winid)
        end

        cnt = cnt + 1
      end
    end)
  )
end

--[[ ▁▁▂▂▃▃▄▄▅▅▆▆▇▇██ ]]
--

function specs.linear_fader(blend, cnt)
  if blend + cnt <= 100 then
    return cnt
  else
    return nil
  end
end

--[[ ▁▁▁▁▂▂▂▃▃▃▄▄▅▆▇ ]]
--

function specs.exp_fader(blend, cnt)
  if blend + math.floor(math.exp(cnt / 10)) <= 100 then
    return blend + math.floor(math.exp(cnt / 10))
  else
    return nil
  end
end

--[[ ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁ ]]
--

function specs.pulse_fader(blend, cnt)
  if cnt < (100 - blend) / 2 then
    return cnt
  elseif cnt < 100 - blend then
    return 100 - cnt
  else
    return nil
  end
end

--[[ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ]]
--

function specs.empty_fader(_, _)
  return nil
end

--[[ ░░▒▒▓█████▓▒▒░░ ]]
--

function specs.shrink_resizer(width, ccol, cnt)
  if width - cnt > 0 then
    return { width - cnt, ccol - (width - cnt) / 2 + 1 }
  else
    return nil
  end
end

--[[ ████▓▓▓▒▒▒▒░░░░ ]]
--

function specs.slide_resizer(width, ccol, cnt)
  if width - cnt > 0 then
    return { width - cnt, ccol }
  else
    return nil
  end
end

--[[ ███████████████ ]]
--

function specs.empty_resizer(width, ccol, cnt)
  if cnt < 100 then
    return { width, ccol - width / 2 }
  else
    return nil
  end
end

local DEFAULT_OPTS = {
  show_jumps = true,
  min_jump = 30,
  popup = {
    delay_ms = 10,
    inc_ms = 5,
    blend = 10,
    width = 20,
    winhl = "PMenu",
    fader = specs.exp_fader,
    resizer = specs.shrink_resizer,
  },
  ignore_filetypes = {},
  ignore_buftypes = {
    nofile = true,
  },
}

function specs.setup(user_opts)
  opts = vim.tbl_deep_extend("force", DEFAULT_OPTS, user_opts)
  specs.create_autocmds()
end

function specs.toggle()
  if au_toggle then
    specs.clear_autocmds()
  else
    specs.create_autocmds()
  end
end

function specs.create_autocmds()
  vim.cmd("augroup Specs")
  vim.cmd("autocmd!")

  if opts.show_jumps then
    vim.cmd("silent autocmd CursorMoved * :lua require('specs').on_cursor_moved()")
  end

  vim.cmd("silent autocmd WinLeave * :lua require('specs').close_active()")

  vim.cmd("augroup END")
  au_toggle = true
end

function specs.clear_autocmds()
  vim.cmd("augroup Specs")
  vim.cmd("autocmd!")
  vim.cmd("augroup END")
  au_toggle = false
end

return specs
