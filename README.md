# OPENWORKS

An open-ended engineering and manufacturing sandbox for Roblox.

`src/` is the authoritative source tree. Studio is the runtime and editor, not the source of truth.

## Quick start

Clone this repository on Windows, install Rojo and Git, open the Openworks place in Roblox Studio, and run `START_OPENWORKS.bat`. Connect the Rojo Studio plugin to `localhost:34872`.

- `START_OPENWORKS.bat` — select a branch, launch Rojo, and start background pull-only Git sync.
- `STOP_OPENWORKS.bat` — stop only this project's tracked development processes.
- `PUSH_OPENWORKS.bat` — commit and push local changes.

See `docs/ARCHITECTURE.md` and `docs/DECISIONS.md` for scope and conventions.
