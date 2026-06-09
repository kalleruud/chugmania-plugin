---
name: openplanet
description: Build, edit, review, and package Openplanet plugins written in AngelScript for Trackmania, Maniaplanet, or Trackmania Turbo. Use when the user mentions Openplanet, Trackmania plugins, .op plugin archives, info.toml metadata, Openplanet callbacks, settings, NadeoServices, VehicleState, or AngelScript plugin code.
---

# Openplanet Plugin Development

## Quick Start

Create or edit plugins as a folder with `info.toml` at the root and one or more `.as` AngelScript files. Openplanet compiles the whole plugin folder as one script module, so avoid duplicate global names across files.

```toml
[meta]
name = "Example Plugin"
author = "Author"
category = "Utilities"
version = "1.0.0"
```

```angelscript
void Main()
{
    print("Hello from Openplanet");
}
```

During development, remind the user that unsigned plugins require Openplanet Developer signature mode. Pack distributable plugins by zipping the contents of the plugin folder, not the folder itself, then rename the `.zip` to `.op`. Plugins need website review/signing to work outside Developer Mode.

## Workflow

1. Inspect `info.toml` first to learn plugin metadata, supported games, dependencies, defines, and exported modules.
2. Inspect `.as` files as one shared module; callback names are global entry points discovered by Openplanet.
3. Use `Main()` for yieldable setup and long-running coroutines. Call `sleep(ms)` for timed waits or `yield()` to resume next render frame.
4. Use `RenderInterface()` for normal UI, `RenderMenu()` or `RenderMenuMain()` for menu entries, `Update(float dt)` for per-frame non-UI logic, and input callbacks only when key/mouse interception is required.
5. Access the game through `CGameCtnApp@ app = GetApp();`; cast explicitly, for example `CTrackMania@ app = cast<CTrackMania>(GetApp());`, and null-check failed casts.
6. Prefer metadata settings (`[Setting ...]` globals and `[SettingsTab]`) over custom persistence unless behavior requires `OnSettingsSave` or `OnSettingsLoad`.
7. Add `[script] dependencies` before using dependency APIs such as `NadeoServices` or `VehicleState`.
8. Gate game-specific code with preprocessor defines such as `TMNEXT`, `MP4`, or `TURBO`; remember `&&` and `||` are evaluated left-to-right without grouping.
9. Search game API classes and members with `https://next.openplanet.dev/search?q=%s` for Trackmania Next (2020), or `https://turbo.openplanet.dev/search?q=%s` for Trackmania Turbo.

## Common Patterns

Settings:

```angelscript
[Setting name="Enabled" description="Enable plugin behavior"]
bool Setting_Enabled = true;

[SettingsTab name="Advanced" icon="Cog"]
void RenderAdvancedSettings()
{
    UI::Text("Advanced settings");
}
```

NadeoServices dependency:

```toml
[script]
dependencies = [ "NadeoServices" ]
```

```angelscript
void Main()
{
    NadeoServices::AddAudience("NadeoLiveServices");
    while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();

    auto req = NadeoServices::Get(
        "NadeoLiveServices",
        NadeoServices::BaseURLLive() + "/api/token/club"
    );
    req.Start();
    while (!req.Finished()) yield();
}
```

VehicleState dependency:

```toml
[script]
dependencies = [ "VehicleState" ]
```

```angelscript
void Update(float dt)
{
    auto vis = VehicleState::ViewingPlayerState();
    if (vis is null) return;
    float rpm = VehicleState::GetRPM(vis);
}
```

## Reference

For game API search URLs, metadata keys, callbacks, settings attributes, auth flow, preprocessor defines, and dependency API notes, see [REFERENCE.md](REFERENCE.md).
