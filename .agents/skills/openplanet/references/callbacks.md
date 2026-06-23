# Plugin Callbacks

Source: https://openplanet.dev/docs/reference/plugin-callbacks

Openplanet discovers callback functions by signature. These are global entry points across the plugin module.

## Core Lifecycle

- `void Main()`: main entry point, yieldable.
- `void OnEnabled()`, `void OnDisabled()`: toggled through plugin state.
- `void OnDestroyed()`: final unload/teardown callback.

## Per-Frame Callbacks

- `void Render()`: render callback every frame.
- `void RenderInterface()`: main UI callback every frame.
- `void RenderMenu()`: overlay menu callback every frame.
- `void RenderMenuMain()`: main menu callback every frame.
- `void RenderEarly()`: earlier render phase; only use when ordering matters.
- `void Update(float dt)`: non-UI per-frame logic; `dt` is delta time.

## Settings And Input

- `void OnSettingsChanged()`: called when a settings-panel value changes.
- `void OnSettingsSave(Settings::Section& section)` and `void OnSettingsLoad(Settings::Section& section)`: custom persistence hooks.
- `OnKeyPress`, `OnMouseButton`, `OnMouseMove`, `OnMouseWheel`: input hooks, with optional `UI::InputBlocking` return values for interception.

## Guidance

- Only `Main()` and other coroutine contexts may yield. UI/render callbacks should not.
- Prefer `RenderInterface()` and `[SettingsTab]` for UI; `RenderSettings()` exists but is deprecated.
- Use the lightest callback that matches the behavior. Avoid input interception unless the plugin genuinely needs it.
