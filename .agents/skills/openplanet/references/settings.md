# Settings

Source: https://openplanet.dev/docs/reference/settings

Openplanet settings are declared with `[Setting ...]` on global variables.

## Supported Shapes

- Scalars: `bool`, signed/unsigned integer types, `float`, `double`, `string`.
- Math types: `vec2`, `vec3`, `vec4`, `int2`, `int3`, `nat2`, `nat3`, `quat`.
- Enums are supported.

## Important Rules

- The initializer defines the default value.
- Values equal to the default are not persisted, so changing a default changes behavior for users who had not customized it.
- Common attributes include `name`, `description`, `category`, `hidden`, `if`, `enableif`, `onchange`, `beforerender`, and `afterrender`.
- Numeric settings can use `min`, `max`, `drag`, and `step`.
- String settings can use `max`, `multiline`, and `password`.
- `vec3` and `vec4` can be marked as `color`.

## Settings UI

- Use `[SettingsTab]` on a global render function for custom settings pages.
- Optional tab attributes include `name`, `icon`, and `order`.
- Prefer declarative settings over manual save/load unless the plugin needs custom storage behavior.
