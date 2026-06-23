# info.toml

Source: https://openplanet.dev/docs/reference/info-toml

`info.toml` lives at the plugin root and defines metadata, game support, and script configuration.

## Main Tables

- `[meta]`: plugin identity and website metadata.
- `[game]`: game-version and supported-game targeting.
- `[script]`: timeout, imports, dependencies, exports, defines, and module behavior.

## Important Fields

- `[meta] name`, `author`, `category`, `version`: the basics every plugin should define.
- `[meta] blocks`: prevents loading alongside listed plugin identifiers.
- `[meta] siteid`: required for Openplanet `Auth`.
- `[meta] essential`: prevents normal disabling; use only with strong justification.
- `[game] supported_games`: use to scope plugins to specific games when behavior differs.
- `[game] min_version` and `max_version`: constrain supported game builds.
- `[script] dependencies`, `optional_dependencies`, `export_dependencies`: plugin dependency graph.
- `[script] imports`: import helper scripts from Openplanet's `Scripts` folder.
- `[script] exports` and `shared_exports`: public AngelScript API surface for dependent plugins.
- `[script] defines`: custom preprocessor flags.
- `[script] timeout`: callback timeout in milliseconds; `0` disables timeout checks.
- `[script] module`: explicit module name, mainly useful for exported APIs.

## Guidance

- Inspect `info.toml` first when orienting in an Openplanet plugin.
- Keep Trackmania Next and Trackmania Turbo support explicit. If a plugin is not truly cross-game, encode that in `supported_games` or preprocessor guards.
- If a plugin talks to external services through Openplanet Auth, verify `siteid` is present before assuming auth can work.
