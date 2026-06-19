# Chugmania Capture Spike

An Openplanet plugin that captures local Trackmania race attempts and sends one
JSON webhook when an attempt ends.

The plugin watches every player in `CurrentPlayground.Players`, including local
split-screen players, and captures:

- player discovery and the controlled split-screen terminal index;
- first accelerator input after each positive start-time transition;
- crossed checkpoint landmarks;
- lap finishes and race finishes;
- map metadata and medal times.

One `race.attempt.ended` request represents the complete attempt and always uses
the same `players[]` format for solo and split screen.

## Webhook settings

Configure the plugin in **Openplanet > Settings > Chugmania Capture Spike**:

- enable **Webhook > Enabled**;
- set **Webhook > Endpoint** to an HTTPS URL;
- set **Webhook > API key**;
- optionally change the retry count.

Requests use `POST`, `Content-Type: application/json`, and the API key is sent
in the `X-API-Key` header. Failed requests are retried after 1, 3, and 10 seconds
by default.

## Payload contract

```json
{
  "schemaVersion": "1.0",
  "eventType": "race.attempt.ended",
  "eventId": "map-uid-1750000000-1",
  "occurredAtUtc": "2026-06-19T20:15:30Z",
  "source": {
    "pluginName": "Chugmania Capture Spike",
    "pluginVersion": "0.1.0",
    "game": "Trackmania"
  },
  "attempt": {
    "attemptId": "map-uid-1750000000-1",
    "format": "split_screen",
    "playerCount": 2,
    "startedAtUtc": "2026-06-19T20:14:42Z",
    "endedAtUtc": "2026-06-19T20:15:30Z",
    "durationMs": 48123,
    "endReason": "all_finished",
    "timingSource": "inferred",
    "map": {
      "uid": "map-uid",
      "name": "Map Name",
      "authorLogin": "author-login",
      "authorName": "Author",
      "mapType": "TrackMania\\TM_Race",
      "mapStyle": "",
      "laps": 1,
      "isLapRace": false,
      "medalTimesMs": { "author": 40000, "gold": 43000, "silver": 47000, "bronze": 55000 }
    },
    "players": [
      {
        "participantKey": "*splitscreen_0*",
        "playerIndex": 0,
        "terminalIndex": 0,
        "login": "*splitscreen_0*",
        "accountId": null,
        "name": "Player 1",
        "isFake": false,
        "isBot": false,
        "spawnIndex": 0,
        "finishPosition": 1,
        "outcome": "finished",
        "firstAccelerator": { "atUtc": "2026-06-19T20:14:44Z", "elapsedMs": 1830 },
        "checkpoints": [
          {
            "sequence": 0,
            "landmarkIndex": 4,
            "landmarkOrder": 0,
            "landmarkTag": "",
            "kind": "checkpoint",
            "atUtc": "2026-06-19T20:14:55Z",
            "elapsedMs": 13210
          }
        ]
      }
    ]
  }
}
```

`endReason` is one of `all_finished`, `restart`, `playground_closed`, or
`map_changed`. Per-player `outcome` is `finished`, `restart`, `quit`, or `dnf`.
The finish landmark is included as the final checkpoint with `kind: "finish"`.

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

Still missing for fully authoritative race capture:

- authoritative race, lap, checkpoint, and sector times;
- authoritative race-start and restart events;
- current lap number and reliable lap-start transitions;
- a canonical checkpoint sequence, because landmark `Order` is not reliable;
- respawn events and counts;
- a stable participant identity beyond the synthetic split-screen login and
  editable display name;
- proof that all supported local modes and multi-lap maps expose the same
  landmark behavior;
- direct detection of every menu-level quit path where the playground remains
  alive;
- persistent delivery across game or plugin shutdown (the retry queue is
  currently in memory);
- an account ID for synthetic split-screen users (`accountId` is `null`).

The tested `CSmScriptPlayer` timing, waypoint-array, lap, end-time, and respawn
fields stayed at zero, `-1`, or empty in both Local Arcade and Split Screen.
`StartTime` changes during setup and can temporarily become `-1`. It is used as
an attempt boundary hint, while elapsed times come from Openplanet's monotonic
clock. The payload therefore reports `timingSource: "inferred"`; a different API
source is required before these times can be called authoritative.

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
- Webhook requests are sent asynchronously from the plugin's main coroutine.
- For distribution outside Developer mode, package the files inside this folder
  as a zip, rename it to `.op`, and submit it for Openplanet signing.
