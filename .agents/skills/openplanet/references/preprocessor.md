# Preprocessor

Source: https://openplanet.dev/docs/reference/preprocessor

Openplanet's AngelScript compiler includes a preprocessor with `#if`, `#elif`, `#else`, and `#endif`.

## Cross-Game Defines

- Trackmania Next: `TMNEXT`
- Trackmania Turbo: `TURBO`
- ManiaPlanet family: `MP4`, `MP40`, `MP41`, plus older legacy defines

## Platform And Signature Defines

- Platform/build examples: `WINDOWS`, `WINDOWS_WINE`, `LINUX`, `MANIA64`, `MANIA32`, `DEVELOPER`, `HAS_DEV`
- Signature mode defines accumulate by level: `SIG_OFFICIAL`, `SIG_REGULAR`, `SIG_SCHOOL`, `SIG_DEVELOPER`
- Competition-profile defines can appear with a `COMP_` prefix

## Important Limitation

- `&&` and `||` are supported, but evaluation is simple left-to-right. Do not assume normal operator precedence or parenthesized grouping.

## Guidance

- Use preprocessor guards for game-specific code paths when one plugin must support both Trackmania Next and Trackmania Turbo.
- Keep guards simple and obvious; split code into helper functions when conditions get hard to read.
