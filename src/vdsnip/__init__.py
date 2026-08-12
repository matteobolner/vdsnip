"""Stream polars DataFrames to a live VisiData pane in Neovim.

Paired with the Neovim plugin in this same repo (``lua/vdsnip``). Your sniprun
kernel is ``Python3_fifo`` (a *persistent* interpreter), so you import once:

    from vdsnip import vd
    vd(df)          # writes df; the vd pane (<leader>vd) auto-reloads

Every later ``vd(df)`` overwrites a shared Arrow file, and the Neovim-side
filesystem watcher tells VisiData to reload it -- so the pane always shows your
latest dataframe as you produce it.

The shared file location is the contract between the two halves. Both read the
``VDSNIP_PATH`` environment variable; the Neovim plugin exports it at startup so
this kernel (a child of Neovim) inherits the exact same value.
"""

from __future__ import annotations

import os
import tempfile

__all__ = ["vd", "arrow_path"]
__version__ = "0.1.0"


def arrow_path() -> str:
    """Resolve the shared Arrow file path.

    Honors ``VDSNIP_PATH`` (set by the Neovim plugin); otherwise falls back to
    ``<tmpdir>/sniprun_vd.arrow`` so ``vdsnip`` is also usable standalone.
    """
    return os.environ.get("VDSNIP_PATH") or os.path.join(
        tempfile.gettempdir(), "sniprun_vd.arrow"
    )


def vd(df, path: str | None = None):
    """Write ``df`` to the shared Arrow file the VisiData pane watches.

    Accepts a polars ``DataFrame``, a polars ``LazyFrame`` (collected first), a
    pyarrow ``Table``, or a pandas ``DataFrame``. Returns ``df`` unchanged so it
    chains: ``vd(df).filter(...)``.

    Note: because it returns the frame, sniprun's nvim-notify will still echo the
    repr. End the line with ``vd(df); None`` to send it *only* to VisiData.
    """
    path = path or arrow_path()
    tmp = path + ".tmp"

    # polars LazyFrame -> materialize before writing
    if hasattr(df, "collect") and not hasattr(df, "write_ipc"):
        df = df.collect()

    if hasattr(df, "write_ipc"):
        df.write_ipc(tmp)  # polars DataFrame -> Arrow IPC (Feather v2)
    else:
        import pyarrow as pa
        import pyarrow.ipc as ipc

        table = df if isinstance(df, pa.Table) else pa.table(df)  # e.g. pandas
        with ipc.new_file(tmp, table.schema) as writer:
            writer.write_table(table)

    # Atomic swap: vd never reads a half-written file, and the watcher sees one
    # clean event per call.
    os.replace(tmp, path)
    return df
