# Chugmania Capture Spike

An Openplanet test plugin for discovering which local Trackmania race data can
be captured before building the Chugmania webhook integration.

The plugin watches every player in `CurrentPlayground.Players`, including local
split-screen players, and prints event records for:

- player discovery and the controlled split-screen terminal index;
- first accelerator input after each positive start-time transition;
- crossed checkpoint landmarks;
- lap finishes and race finishes;
- detailed player state at every event, including controls, position, speed,
  engine state, wheel contact, and skid/air duration;
- map metadata and medal times.

`FIRST_ACCELERATOR` is emitted on the first frame after a positive start-time
transition where that player's `InputGasPedal` is greater than `0.01`.

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

Useful event names are `FIRST_ACCELERATOR`, `CHECKPOINT`, `LAP_FINISH`, and
`RACE_FINISH`. Each event is followed by a `SNAPSHOT` record.

## Capture status

Validated in Local Arcade and local Split Screen:

- map metadata and medal targets;
- separate players with synthetic split-screen logins and terminal indices;
- per-player accelerator input after an attempt is armed;
- per-player checkpoint, lap-finish, and race-finish landmarks;
- controls, position, velocity, speed, engine, wheel, skid, and air state.

Still missing for a complete race capture:

- authoritative race, lap, checkpoint, and sector times;
- authoritative race-start and restart events;
- current lap number and reliable lap-start transitions;
- a canonical checkpoint sequence, because landmark `Order` is not reliable;
- respawn events and counts;
- a stable participant identity beyond the synthetic split-screen login and
  editable display name;
- proof that all supported local modes and multi-lap maps expose the same
  landmark behavior;
- webhook configuration, payload schema, retries, deduplication, and delivery.

The tested `CSmScriptPlayer` timing, waypoint-array, lap, end-time, and respawn
fields stayed at zero, `-1`, or empty in both Local Arcade and Split Screen.
`StartTime` changes during setup and can temporarily become `-1`, so it is used
only to re-arm accelerator detection and is not published as a race-start
event. A different API source is required for timing and race-progress data.

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
- Checkpoints are detected from each player's crossed map landmark.
- The plugin only prints data. It does not make network requests yet.
- For distribution outside Developer mode, package the files inside this folder
  as a zip, rename it to `.op`, and submit it for Openplanet signing.
