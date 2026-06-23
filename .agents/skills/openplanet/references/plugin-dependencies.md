# Plugin Dependencies

Source: https://openplanet.dev/docs/tutorials/plugin-dependencies

- Openplanet plugins can depend on other plugins through `[script] dependencies = [ "PluginName" ]` in `info.toml`.
- A dependency must be installed for the dependent plugin to load. This matters for both Trackmania Next and Trackmania Turbo plugins that rely on shared helper modules.
- Dependencies expose APIs through exported script files, not by sharing arbitrary runtime state.

## Key Concepts

- `dependencies`: required plugins.
- `optional_dependencies`: plugins that can be used when present but are not mandatory.
- `exports`: script files compiled into dependent plugins but not into the exporting plugin itself.
- `shared_exports`: script files compiled into both the exporting plugin and dependent plugins. Use this when shared classes or other shared AngelScript entities are needed.
- `export_dependencies`: dependencies re-exported to dependents.

## Practical Notes

- Treat export files like headers or public API surfaces. Keep signatures stable and update both declaration and implementation when changing exported functions.
- Function exports are commonly wrapped in a namespace to avoid collisions.
- Because Openplanet compiles plugin folders as modules, exported names still need clear namespacing and version discipline.
- Common dependencies in this ecosystem include `NadeoServices`, `VehicleState`, `Camera`, and `Controls`.
