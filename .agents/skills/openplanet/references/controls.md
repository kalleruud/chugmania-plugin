# Controls

Source: https://openplanet.dev/docs/reference/controls

`Controls` is an Openplanet dependency that provides reusable UI components.

## Setup

- Add `[script] dependencies = [ "Controls" ]` to `info.toml`.
- The dependency offers a demo window in its settings so you can inspect available controls visually.

## Useful Controls

- `Controls::Tag(...)`: inline status tag at the current UI cursor position.
- Convenience variants such as `TagPrimary`, `TagInfo`, `TagLink`, `TagSuccess`, `TagWarning`, and `TagDanger`.
- `Controls::DrawTag(...)`: draw a tag at an explicit screen position outside normal UI layout.
- `Controls::Frame(...)`: colored framed content block for warnings, info, or grouped text.

## Guidance

- Use `Controls` when you want shared styling instead of hand-rolling every UI primitive.
- Keep text labels readable without relying on color alone.
