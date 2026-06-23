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
- Refresh the cached Openplanet HTML references with `bun scripts/update_op_skill.ts`.

## Reference Files

- `references/plugin-dependencies.html`: cached Openplanet docs for dependency loading, `exports`, and `shared_exports`.
- `references/info-toml.html`: cached Openplanet docs for plugin metadata, game targeting, and script config.
- `references/callbacks.html`: cached Openplanet docs for lifecycle, render, menu, input, and settings callbacks.
- `references/icons.html`: cached Openplanet docs for built-in icon constants.
- `references/settings.html`: cached Openplanet docs for `[Setting]`, supported types, defaults, and `[SettingsTab]`.
- `references/imports.html`: cached Openplanet docs for script imports and deprecations.
- `references/preprocessor.html`: cached Openplanet docs for `#if` flow, defines, and cross-game guards.
- `references/authentication.html`: cached Openplanet docs for Openplanet Auth setup and token validation.
- `references/nadeoservices.html`: cached Openplanet docs for NadeoServices setup and request helpers.
- `references/vehiclestate.html`: cached Openplanet docs for viewed-player state and vehicle helpers.
- `references/camera.html`: cached Openplanet docs for camera projection/query helpers.
- `references/controls.html`: cached Openplanet docs for reusable UI helpers.
- `references/trackmania-webservices.md`: hand-written Trackmania Web Services guide for domains, auth, and OAuth separation.
