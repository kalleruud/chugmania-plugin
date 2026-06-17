# Chugmania Capture Spike

An Openplanet test plugin for discovering which local Trackmania race data can
be captured before building the Chugmania webhook integration.

The plugin watches every player in `CurrentPlayground.Players`, including local
split-screen players, and prints event records for:

- player discovery and the controlled split-screen terminal index;
- race and lap starts;
- first accelerator input after each lap start;
- lap and race waypoint/checkpoint times;
- lap finishes and race finishes;
- detailed player state at every event, including timing arrays, respawns,
  controls, position, speed, engine state, wheel contact, and skid/air duration;
- map metadata and medal times.

`FIRST_ACCELERATOR.delayMs` uses that player's `CurrentLapTime` at the first
frame where `InputGasPedal` is greater than `0.01`. This is frame-polled, so its
precision is limited by the game's render frame rate.

## Run the test

1. Install Openplanet for Trackmania 2020 and enable **Developer** signature
   mode in Openplanet's settings. Unsigned local plugins only load in this mode.
2. Copy this repository folder into the Openplanet `Plugins` directory. Keep
   `info.toml` at the copied folder's root, for example:
   `OpenplanetNext/Plugins/ChugmaniaCaptureSpike/info.toml`. Alternatively,
   copy `dist/ChugmaniaCaptureSpike.op` directly into the `Plugins` directory.
3. Start Trackmania, then reload plugins from Openplanet's plugin manager. The
   log should contain `Capture test loaded`.
4. Start **Local > Arcade** or a local **Split Screen** race. Complete
   checkpoints and at least one lap with every controller/player.
5. Inspect the Openplanet log/console and filter for
   `[Chugmania Capture Spike]`. Compare `playerIndex`, `login`, `name`, and
   `terminal` to identify each split-screen player.

Useful event names are `FIRST_ACCELERATOR`, `LAP_WAYPOINT`, `LAP_FINISH`, and
`RACE_FINISH`. Each event is followed by a `SNAPSHOT` and four `TIMES` records.

## Development notes

Package the plugin locally with the script for your platform. Both scripts read
the name and version from `info.toml` and create
`dist/chugmania-capture-spike-v0.0.1.op` by default.

```powershell
.\scripts\build-op.ps1
```

```bash
bash ./scripts/build-op.sh
```

Pass an output directory as the first argument to place the artifact elsewhere.

- This spike targets Trackmania 2020 (`TMNEXT`) APIs.
- Checkpoints are primarily detected from each player's crossed map landmark.
  The game also exposes waypoint time arrays, but those can be empty in some
  modes, so the plugin logs both sources for comparison.
- The plugin only prints data. It does not make network requests yet.
- For distribution outside Developer mode, package the files inside this folder
  as a zip, rename it to `.op`, and submit it for Openplanet signing.
