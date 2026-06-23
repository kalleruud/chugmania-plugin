# Imports

Source: https://openplanet.dev/docs/reference/imports

Openplanet can import optional helper scripts from its `Scripts` folder through `[script] imports`.

## Notes

- Some older imports have been folded into Openplanet itself and no longer need manual import declarations.
- Deprecated imports called out by the docs include `Icons.as`, `Permissions.as`, `Time.as`, and `Formatting.as`.
- `Dialogs.as` is documented as subject to removal.

## Guidance

- Do not add imports just because old examples used them; verify whether the helper is already built in.
- Keep imports minimal and document why each import is still needed.
- If a plugin already works without a legacy import, prefer removing the import rather than keeping dead config.
