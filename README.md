# vdsnip

Stream [polars](https://pola.rs) DataFrames to a live [VisiData](https://visidata.org)
pane in Neovim, as you produce them with [sniprun](https://github.com/michaelb/sniprun).

VisiData is a full-screen terminal UI, so it can't render inside an nvim-notify
popup — it needs its own pane. `vdsnip` gives it one: your snippet writes the
frame to a shared Arrow file, and a Neovim-side filesystem watcher tells the vd
pane to reload. Wrap a frame in `vd(...)` and it shows up in VisiData; everything
else keeps flowing to nvim-notify.

This repo ships **both halves**:

| Half | Installed by | Path |
| --- | --- | --- |
| Python package `vdsnip` | uv / pip | `src/vdsnip` |
| Neovim plugin `vdsnip.nvim` | lazy.nvim | `lua/vdsnip` |

They agree on the shared file via the `VDSNIP_PATH` environment variable, which
the Neovim plugin exports at startup so the sniprun kernel inherits it.

## Requirements

- `vd` (VisiData) on `PATH`, with `pyarrow` available to it (for the Arrow loader)
- sniprun configured with a **persistent** Python interpreter (`Python3_fifo`)
- polars in your project

## Install — Python half (uv)

Run this in the project whose venv your sniprun kernel uses:

```sh
uv add "vdsnip @ git+https://github.com/matteobolner/vdsnip"
# feeding pandas frames instead of polars? add the extra:
# uv add "vdsnip[pandas] @ git+https://github.com/matteobolner/vdsnip"
```

Because you launch Neovim from inside the project, the `Python3_fifo` kernel
picks up that venv's `python` and sees `vdsnip` — no `PYTHONPATH` juggling.

## Install — Neovim half (lazy.nvim)

```lua
{
  'matteobolner/vdsnip',
  config = function()
    require('vdsnip').setup {
      -- path = '/tmp/sniprun_vd.arrow',   -- shared Arrow file (also $VDSNIP_PATH)
      -- open = 'botright split | resize 20', -- or 'vsplit' / 'tabnew'
      -- keymap = '<leader>vd',            -- false to skip
      -- debounce = 80,                    -- ms
    }
  end,
}
```

## Use

```python
from vdsnip import vd     # once per kernel session (it's persistent)

df = pl.read_csv("data.csv")
vd(df)                    # run this snippet, then hit <leader>vd once
```

- `<leader>vd` (or `:VdLive`) opens the pane; `:VdClose` dismisses it.
- After the pane is open, every `vd(df)` auto-refreshes it to the newest frame.
- `vd(df)` returns `df` for chaining; end with `vd(df); None` to keep the repr
  out of nvim-notify.

Accepts polars `DataFrame`/`LazyFrame`, pyarrow `Table`, and pandas `DataFrame`.

## License

MIT
