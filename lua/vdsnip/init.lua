-- vdsnip.nvim -- live VisiData view of polars dataframes produced by sniprun.
--
-- Pairs with the `vdsnip` Python package (same repo). Flow:
--   1. In your snippets:  `from vdsnip import vd`  then  `vd(df)`
--   2. Open the pane once with `<leader>vd` (or `:VdLive`) -- runs `vd` in a
--      terminal split on the shared Arrow file.
--   3. Every later `vd(df)` rewrites that file; a libuv fs watcher sends vd a
--      Ctrl-R (reload-sheet), so the pane live-updates to your newest frame.
--
-- The Python and Lua halves agree on the file via the VDSNIP_PATH env var, which
-- setup() exports so the sniprun kernel (a child of Neovim) inherits it.

local M = {}

local uv = vim.uv or vim.loop

local RELOAD = '\18' -- Ctrl-R = VisiData's reload-sheet

local config = {
  path = nil, -- resolved in setup(); also exported as $VDSNIP_PATH
  open = 'botright split | resize 20', -- window command; try 'vsplit' / 'tabnew'
  keymap = '<leader>vd', -- set to false to skip the mapping
  debounce = 80, -- ms to coalesce rapid writes before reloading
}

local state = {
  bufnr = nil,
  chan = nil,
  win = nil,
  watcher = nil,
  debounce = nil,
  dir = nil,
  name = nil,
}

local function pane_alive()
  return state.chan ~= nil and state.bufnr ~= nil and vim.api.nvim_buf_is_valid(state.bufnr)
end

local function stop_watcher()
  if state.watcher then
    state.watcher:stop()
    if not state.watcher:is_closing() then
      state.watcher:close()
    end
    state.watcher = nil
  end
  if state.debounce then
    state.debounce:stop()
    if not state.debounce:is_closing() then
      state.debounce:close()
    end
    state.debounce = nil
  end
end

local function send_reload()
  if pane_alive() then
    pcall(vim.api.nvim_chan_send, state.chan, RELOAD)
  end
end

-- Watch the *directory* (not the file): survives the atomic rename the Python
-- side does. Filter events to our filename, then debounce.
local function start_watcher()
  stop_watcher()
  state.watcher = uv.new_fs_event()
  state.watcher:start(state.dir, {}, function(err, fname)
    if err or fname ~= state.name then
      return
    end
    if not state.debounce then
      state.debounce = uv.new_timer()
    end
    state.debounce:stop()
    state.debounce:start(config.debounce, 0, function()
      vim.schedule(send_reload)
    end)
  end)
end

local function open_pane()
  if pane_alive() then
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
    return
  end

  if uv.fs_stat(config.path) == nil then
    vim.notify('vdsnip: no dataframe yet -- run `vd(df)` in a snippet first.', vim.log.levels.WARN)
    return
  end

  vim.cmd(config.open)
  state.win = vim.api.nvim_get_current_win()

  state.chan = vim.fn.termopen({ 'vd', config.path }, {
    on_exit = function()
      state.chan = nil
      state.bufnr = nil
      state.win = nil
      stop_watcher()
    end,
  })
  state.bufnr = vim.api.nvim_get_current_buf()
  vim.bo[state.bufnr].bufhidden = 'wipe'

  start_watcher()
  vim.cmd 'startinsert'
end

local function close_pane()
  if pane_alive() then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end
end

function M.setup(opts)
  config = vim.tbl_extend('force', config, opts or {})

  -- Resolve the shared path and export it so the Python kernel agrees exactly.
  config.path = config.path or vim.env.VDSNIP_PATH or '/tmp/sniprun_vd.arrow'
  vim.env.VDSNIP_PATH = config.path
  state.dir = vim.fs.dirname(config.path)
  state.name = vim.fs.basename(config.path)

  vim.api.nvim_create_user_command('VdLive', open_pane, { desc = 'Open live VisiData view of last dataframe' })
  vim.api.nvim_create_user_command('VdClose', close_pane, { desc = 'Close VisiData view' })

  if config.keymap then
    vim.keymap.set('n', config.keymap, open_pane, { desc = '[V]isi[D]ata live dataframe view' })
  end
end

return M
