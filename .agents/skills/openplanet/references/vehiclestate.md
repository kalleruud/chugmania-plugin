# VehicleState

Source: https://openplanet.dev/docs/reference/vehiclestate

`VehicleState` provides vehicle and viewed-player state helpers for gameplay plugins.

## Setup

- Add `[script] dependencies = [ "VehicleState" ]` to `info.toml`.
- The dependency includes a debug window in its own settings, which is useful when discovering live state.

## Common Accessors

- `VehicleState::GetViewingPlayer()`: currently viewed player; type differs by game.
- `VehicleState::ViewingPlayerState()`: current viewed vehicle state and may still be valid when the player object is null.
- `VehicleState::GetRPM(...)`
- `VehicleState::GetSideSpeed(...)`

## Trackmania-Specific Helpers

- Trackmania-only helpers include wheel dirt, wheel falling state, turbo level, reactor timer, cruise display speed, and vehicle type queries.
- Wheel indices are `0` front-left, `1` front-right, `2` rear-left, `3` rear-right`.

## Guidance

- Be explicit about game differences: Trackmania Next returns the native Trackmania state type, while ManiaPlanet and Trackmania Turbo may expose wrapper behavior or subsets.
- Null-check state before reading live telemetry.
