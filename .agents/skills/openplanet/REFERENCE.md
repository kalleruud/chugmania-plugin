# Openplanet Reference Notes

Sources distilled from Openplanet docs pages requested on 2026-06-09:

- https://openplanet.dev/docs/tutorials/writing-plugins
- https://openplanet.dev/docs/tutorials/entry-point-execution
- https://openplanet.dev/docs/tutorials/app-object
- https://openplanet.dev/docs/reference/info-toml
- https://openplanet.dev/docs/reference/plugin-callbacks
- https://openplanet.dev/docs/reference/settings
- https://openplanet.dev/docs/reference/preprocessor
- https://openplanet.dev/docs/reference/auth
- https://openplanet.dev/docs/reference/nadeoservices
- https://openplanet.dev/docs/reference/vehiclestate

## Plugin Layout And Loading

- Plugins are written in AngelScript.
- Custom plugins live in the user's Openplanet `Plugins` folder, whose exact parent differs by game/version.
- Modern plugins require root `info.toml` plus script files.
- Openplanet loads a plugin folder as one script module, effectively merging all `.as` code. Shared globals, classes, and functions must not collide.
- `void Main()` is the primary entry point and is yieldable. `sleep(1000)` suspends for 1 second; `sleep(0)` and `yield()` resume next render frame.
- Openplanet plugins run at render framerate, not ManiaScript's fixed 100 FPS.
- `.op` files are zip archives renamed to `.op`; zip the files inside the plugin folder, do not password-protect, and do not use rar.
- Unsigned plugins need Developer signature mode. Public distribution requires website submission/review/signing.

## `info.toml`

`[meta]`:

- `version` string: required for website submission, defaults to `1.0` locally if omitted.
- `name` string: displayed plugin name, defaults to identifier if omitted.
- `author` string.
- `category` string: defaults to `Uncategorized`; prefer existing category names.
- `blocks` string array: plugin identifiers to prevent loading with this plugin.
- `perms` string: deprecated; avoid and use Permissions API instead.
- `siteid` integer: website plugin ID, needed for `Auth` API; review usually adds it unless auth needs manual setup.
- `essential` boolean: prevents users disabling the plugin; use only with a strong reason.

`[game]`:

- `min_version` / `max_version`: date or UTC date-time such as `2022-02-03` or `2022-02-03 18:03`.
- `supported_games`: string array; empty means all games. Available from Openplanet 1.29.10.

`[script]`:

- `timeout`: callback timeout in milliseconds. `0` disables timeout and overhead, but can hang on infinite loops.
- `imports`: scripts from Openplanet's `Scripts` folder.
- `exports`: files exported to dependent plugins, compiled into dependents but not this plugin.
- `shared_exports`: exported files also compiled into this plugin.
- `dependencies`: required plugin identifiers.
- `optional_dependencies`: optional plugin identifiers.
- `export_dependencies`: dependencies re-exported to plugins that depend on this plugin.
- `defines`: custom preprocessor defines.
- `module`: explicit module name, mainly for exported APIs.
- `controls_other_plugins`: suppresses plugin-control warning notifications when truly necessary. Available from 1.29.10.

## Callback Functions

- `void Main()`: main yieldable entry point.
- `void Render()`: every frame render hook.
- `void RenderInterface()`: every frame UI render hook.
- `void RenderMenu()`: every frame for Openplanet menu UI items.
- `void RenderMenuMain()`: every frame for main menu UI items.
- `void RenderSettings()`: deprecated; use `[SettingsTab]`.
- `void RenderEarly()`: before regular render callbacks; rarely needed.
- `void Update(float dt)`: every frame, with delta time in milliseconds.
- `void OnDisabled()`, `void OnEnabled()`, `void OnDestroyed()`: plugin lifecycle.
- `void OnSettingsChanged()`: setting changed from settings panel.
- `void OnSettingsSave(Settings::Section& section)`, `void OnSettingsLoad(Settings::Section& section)`: custom settings persistence.
- `void OnKeyPress(bool down, VirtualKey key)` or `UI::InputBlocking OnKeyPress(...)`: keyboard.
- `void OnMouseButton(bool down, int button, int x, int y)` or `UI::InputBlocking OnMouseButton(...)`: mouse button.
- `void OnMouseMove(int x, int y)`: viewport mouse movement.
- `void OnMouseWheel(int x, int y)` or `UI::InputBlocking OnMouseWheel(...)`: wheel delta.
- `void OnLoadCallback(CMwNod@ nod)`: early Nod load callback after `RegisterLoadCallback`; avoid unless needed.

## Settings

Declare a global variable with `[Setting ...]`. Supported types include bool, signed/unsigned ints, floats, strings, vectors (`vec2`/`vec3`/`vec4`, `int2`/`int3`, `nat2`/`nat3`), `quat`, and enums.

Defaults come from the global initializer. Values equal to default are not saved, so changing a default changes behavior for users who were still on that default.

Common attributes:

- `name`, `description`, `category`.
- `hidden` for programmatic storage.
- `if` and `enableif` with boolean, enum, or function conditions, including `!` negation.
- `onchange`, `beforerender`, `afterrender`, each pointing to a global `void Func()`.

Type-specific attributes:

- Numeric: `min`, `max`, `drag`, `step`.
- `vec3` / `vec4`: `color`.
- `string`: `max`, `multiline`, `password`.

Scripted settings tabs use `[SettingsTab]` on a global render function. Optional attributes include `name`, `icon`, and `order`.

## App Object

- `CGameCtnApp@ GetApp()` returns the main game app object.
- Use `CGameCtnApp` as the stable base class.
- Explicit casts are required for child APIs, e.g. `CTrackMania@ app = cast<CTrackMania>(GetApp());`.
- Failed casts return `null`; check before use.

## Preprocessor

Use `#if`, `#elif`, `#else`, `#endif`. `&&` and `||` exist but are basic: they evaluate left-to-right, no precedence, no parentheses.

Common game/platform defines:

- Games: `TMNEXT`, `MP4`, `MP40`, `MP41`, `TURBO`, `MP3`, `FOREVER`, `UNITED_FOREVER`, `NATIONS_FOREVER`.
- Build/platform: `LOGS`, `HAS_DEV`, `SERVER`, `MANIA64`, `MANIA32`, `WINDOWS`, `WINDOWS_WINE`, `LINUX`, `DEVELOPER`.

Signature defines are active when current signature mode is at or below their level:

- Official: `SIG_OFFICIAL`
- Regular: `SIG_OFFICIAL`, `SIG_REGULAR`
- School: `SIG_OFFICIAL`, `SIG_REGULAR`, `SIG_SCHOOL`
- Developer: `SIG_OFFICIAL`, `SIG_REGULAR`, `SIG_SCHOOL`, `SIG_DEVELOPER`

Competition profiles can expose `COMP_...` defines.

## Authentication API

Use Openplanet Auth when a plugin must prove the player's identity to the plugin's own backend.

Setup:

- Create the plugin on the website.
- Enable Authentication in plugin admin settings.
- Add `[meta] siteid = <numeric id>` manually.
- Keep the server-side secret on the backend only.

Client flow:

```angelscript
auto tokenTask = Auth::GetToken();
while (!tokenTask.Finished()) yield();
string token = tokenTask.Token();
```

Server flow:

- POST `application/x-www-form-urlencoded` to `https://openplanet.dev/api/auth/validate`.
- Body: `token=<client_token>&secret=<plugin_secret>`.
- Reject any response with `error`.
- Successful response includes `account_id`, `display_name`, and `token_time`.
- Intermediate tokens are intentionally short-lived; exchange them for your own persistent token when needed.

## NadeoServices Dependency

Use `NadeoServices` for Nadeo API requests from plugins. It manages game auth tokens cleanly and prevents multiple plugins from fighting over token access.

Add:

```toml
[script]
dependencies = [ "NadeoServices" ]
```

Audiences:

- `NadeoLiveServices`: Live and Meet API.
- `NadeoServices`: Core API.

Core calls:

- `NadeoServices::AddAudience(audience)`
- `NadeoServices::IsAuthenticated(audience) -> bool`
- `NadeoServices::GetAccountID() -> string`
- `NadeoServices::BaseURLCore()`, `BaseURLLive()`, `BaseURLMeet()`
- Authenticated HTTP helpers: `Request`, `Get`, `Post`, `Put`, `Delete`, `Patch`.
- `GetDisplayNameAsync(accountId)` and `GetDisplayNamesAsync(accountIds)` must be called from yieldable functions.
- `LoginToAccountId(login)` and `AccountIdToLogin(accountId)` convert identifiers.

## VehicleState Dependency

Use `VehicleState` for current vehicle and watched-player state.

Add:

```toml
[script]
dependencies = [ "VehicleState" ]
```

Useful calls:

- `VehicleState::GetViewingPlayer()` returns the local/spectated player object. Type differs by game.
- `VehicleState::ViewingPlayerState()` returns the viewed vehicle state and may be valid even when the viewing player is null.
- `GetRPM(vis)`, `GetSideSpeed(vis)`.
- Trackmania-only helpers: `GetWheelDirt(vis, w)`, `GetWheelFalling(vis, w)`, `GetLastTurboLevel(vis)`, `GetReactorFinalTimer(vis)`, `GetCruiseDisplaySpeed(vis)`, `GetVehicleType(vis)`.
- Vis lookup: `GetVis(sceneVis, player)`, `GetVisFromId(sceneVis, vehicleEntityId)`, `GetSingularVis(sceneVis)`, `GetAllVis(sceneVis)`.
- Wheel indices: `0` front-left, `1` front-right, `2` rear-left, `3` rear-right.

VehicleState has a debug window in its plugin settings for inspecting live state.
