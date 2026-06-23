# Icons

Source: https://openplanet.dev/docs/reference/icons

Openplanet exposes a large set of built-in icon constants under `Icons::...`.

## Usage

- Use icon constants in labels for menus, settings tabs, windows, and UI text.
- Typical examples include `Icons::Cog`, `Icons::Search`, `Icons::Check`, `Icons::Times`, and game/community-specific icons like `Icons::TrackmaniaT`.
- Icons are plain string constants, so they can be concatenated with text labels.

## Guidance

- Prefer built-in icons over custom glyph hacks.
- Choose icons for readability first; do not rely on icons alone to communicate important state.
- Keep icon usage consistent across Trackmania Next and Trackmania Turbo UIs unless a game-specific icon is intentional.
