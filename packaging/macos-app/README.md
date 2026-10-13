# macOS launcher app

A double-clickable wrapper around the CLI, for people who would rather not keep
a terminal open:

1. It asks **Mirror only** or **Mirror + Record** (or Cancel).
2. If more than one device is attached, it asks which one to use.
3. Recording sessions are written to `~/Movies/ioscpy-<timestamp>.mp4`, named
   from the moment the app was launched. A reconnect continues in
   `ioscpy-<timestamp>-2.mp4` rather than overwriting what was captured.
4. Closing the mirror window, pressing Ctrl-C, or quitting the app all finalize
   the file the same way, because the app forwards a quit as Ctrl-C.

## Build

```bash
./packaging/macos-app/build-app.sh              # into ~/Applications
./packaging/macos-app/build-app.sh /Applications
```

The app calls `ioscpy` from `PATH` (`~/Movies` recordings and `~/Library/Logs/ioscpy`
for logs), so install the CLI first: `brew install ioscpy`, or build it from source
with `cargo install --path host`.

## Requirements

Recording uses the `--record` flag, which lives on the `feat/record-mp4` branch
(PR #16). Without it, **Mirror + Record** fails with an unknown-option error and
the app reports that nothing was recorded.

## Testing without dialogs

The launcher reads a few environment variables, which is also how it is exercised
in CI-style smoke tests:

```bash
IOSCPY_LAUNCHER_QUIET=1 IOSCPY_LAUNCHER_MODE=record \
  IOSCPY_LAUNCHER_UDID=<udid> \
  ~/Applications/ioscpy.app/Contents/MacOS/ioscpy-launcher
```
