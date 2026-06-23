---
name: openplanet
description: Build, edit, review, and package Openplanet plugins written in AngelScript for Trackmania, Maniaplanet, or Trackmania Turbo. Use when the user mentions Openplanet, Trackmania plugins, .op plugin archives, info.toml metadata, Openplanet callbacks, settings, NadeoServices, VehicleState, or AngelScript plugin code.
---

# Openplanet Skill

## What These Tools Are

- Trackmania is the racing game family this repo targets. Support both Trackmania Next (2020) and Trackmania Turbo; only assume ManiaPlanet when the code or user says so.
- Openplanet is the plugin runtime, overlay, and API surface used to extend Trackmania-family games with plugins, UI, callbacks, settings, and dependency modules.
- AngelScript is the scripting language used by Openplanet plugins. A plugin folder is compiled as one module, so globals, classes, and functions must not collide across `.as` files.

## Tutorial Summary

- Writing plugins: create a plugin folder with root `info.toml` plus AngelScript files, enable Developer signature mode for unsigned local work, test through the overlay, and package releases by zipping plugin contents into a `.op` archive.
- Entry point execution: `Main()` is the first callback and is yieldable; use `sleep(ms)` or `yield()` to hand control back, and remember Openplanet runs at render-frame cadence rather than ManiaScript's fixed tick rate.
- Menu options: `RenderMenu()` is a per-frame non-yieldable UI callback; use immediate-mode helpers like `UI::MenuItem(...)` to add overlay menu actions.
- The app object: `GetApp()` returns `CGameCtnApp@`; cast to more specific game types when needed and null-check failed casts before using game-specific fields.

## API Search

- Replace `%s` with the search term.
- Openplanet API: `https://openplanet.dev/docs/api/search?q=%s`
- Trackmania Next API: `https://next.openplanet.dev/search?q=%s`
- Trackmania Turbo API: `https://turbo.openplanet.dev/search?q=%s`
- ManiaPlanet API: `https://mp4.openplanet.dev/search?q=%s`
- Use the API that matches the game/runtime you are editing. For in-game web requests, also consult the Web Services reference below.

## Reference Files

- `references/plugin-dependencies.md`: dependency loading, `exports`, `shared_exports`, and cross-plugin APIs.
- `references/info-toml.md`: plugin metadata, game targeting, script config, defines, imports, and dependency keys.
- `references/callbacks.md`: lifecycle, render, menu, input, and settings callbacks.
- `references/icons.md`: built-in icon constants and practical usage notes.
- `references/settings.md`: `[Setting]`, supported types, defaults, attributes, and `[SettingsTab]`.
- `references/imports.md`: Openplanet script imports, deprecated imports, and removal notes.
- `references/preprocessor.md`: `#if` flow, game/platform/signature defines, and cross-game guards.
- `references/authentication.md`: Openplanet Auth setup, token flow, backend validation, and persistence guidance.
- `references/nadeoservices.md`: NadeoServices dependency setup, audiences, auth readiness, and request helpers.
- `references/vehiclestate.md`: viewed-player state access and vehicle helpers across supported games.
- `references/camera.md`: camera projection/query helpers for world-to-screen work.
- `references/controls.md`: reusable UI controls such as tags and frames.
- `references/trackmania-webservices.md`: Trackmania Web Services domains, auth paths, OAuth separation, and safe usage guidance.
