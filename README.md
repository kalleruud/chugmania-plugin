# New Openplanet Plugin

Skeleton for a new Openplanet plugin.

## Structure

- `info.toml`: plugin metadata, dependencies, exports, and defines.
- `src/Main.as`: Openplanet lifecycle callbacks and coroutine entry points.
- `src/Settings.as`: user-facing settings and settings tabs.
- `src/Interface/Window.as`: placeholder UI rendering.
- `src/Utils/Helpers.as`: shared helper placeholders.
- `src/Exports/Exports.as`: optional public API placeholder.

During development, unsigned plugins require Openplanet Developer signature mode.
To distribute the plugin, zip the contents of this folder and rename the archive to `.op`.
