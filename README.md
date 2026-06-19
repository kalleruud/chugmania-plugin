# Chugmania Webhooks

An Openplanet plugin that captures local Trackmania race attempts and sends one
JSON webhook when an attempt ends.

The plugin watches every player in `CurrentPlayground.Players`, including local
split-screen players, and captures:

- player discovery and the controlled split-screen terminal index;
- first accelerator input after each positive start-time transition;
- authoritative start, checkpoint, respawn, finish, restart, quit, and DNF events;
- map metadata and medal times.

One `race.attempt.ended` request represents the complete attempt and always uses
the same `players[]` format for solo and split screen. Race durations and
checkpoint times come from MLFeed's ManiaScript-backed game clock.

## Webhook settings

Configure the plugin in **Openplanet > Settings > Chugmania Webhooks**:

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
  "schemaVersion": "1.1",
  "eventType": "race.attempt.ended",
  "eventId": "map-uid-1750000000-1",
  "occurredAtUtc": "2026-06-19T20:15:30.123Z",
  "source": {
    "pluginName": "Chugmania Webhooks",
    "pluginVersion": "0.1.0",
    "game": "Trackmania"
  },
  "attempt": {
    "attemptId": "map-uid-1750000000-1",
    "format": "split_screen",
    "playerCount": 2,
    "startedAtUtc": "2026-06-19T20:14:42.000Z",
    "endedAtUtc": "2026-06-19T20:15:30.123Z",
    "durationMs": 48123,
    "endReason": "all_finished",
    "timingSource": "mlfeed_game_clock",
    "map": {
      "uid": "map-uid",
      "name": "Map Name",
      "authorLogin": "author-login",
      "authorName": "Author",
      "mapType": "TrackMania\\TM_Race",
      "mapStyle": "",
      "laps": 1,
      "isLapRace": false,
      "checkpointsPerLap": 3,
      "waypointsToFinish": 4,
      "mlFeedLapCount": 1,
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
        "isLocalPlayer": true,
        "spawnIndex": 0,
        "finishPosition": 1,
        "outcome": "finished",
        "currentLap": 1,
        "checkpointsPassed": 4,
        "finalRaceTimeMs": 48123,
        "theoreticalRaceTimeMs": 47123,
        "sessionBestTimeMs": 48123,
        "ranks": { "race": 1, "raceWithRespawns": 1, "timeAttack": 1 },
        "respawns": {
          "count": 1,
          "timeLostMs": 1000,
          "lastCheckpointIndex": 1,
          "lastAtDurationMs": 15000
        },
        "timingDiagnostics": { "latencyEstimateMs": 16.5, "latencySampleCount": 8.0 },
        "sessionBest": {
          "raceCheckpointTimesMs": [0, 13210, 25000, 37000, 48123],
          "raceIsComplete": true,
          "lapCheckpointTimesMs": [0, 13210, 25000, 37000, 48123],
          "lapIsComplete": true
        },
        "firstAccelerator": { "atUtc": "2026-06-19T20:14:44.830Z", "durationMs": 1830 },
        "events": [
          {
            "sequence": 0,
            "type": "start",
            "atUtc": "2026-06-19T20:14:43.000Z",
            "durationMs": 0
          },
          {
            "sequence": 1,
            "type": "checkpoint",
            "atUtc": "2026-06-19T20:14:56.210Z",
            "durationMs": 13210,
            "checkpoint": { "index": 1, "lap": 1, "lapCheckpointIndex": 1 },
            "splitDurationMs": 13210,
            "theoreticalDurationMs": 13210,
            "respawnCountAtCheckpoint": 0,
            "timeLostToRespawnsMs": 0
          },
          {
            "sequence": 2,
            "type": "respawn",
            "atUtc": "2026-06-19T20:14:58.000Z",
            "durationMs": 15000,
            "respawn": {
              "ordinal": 1,
              "checkpointIndex": 1,
              "timeLostToRespawnsMs": 1000
            }
          }
        ]
      }
    ]
  }
}
```

`endReason` is one of `all_finished`, `restart`, `playground_closed`, or
`map_changed`. Per-player `outcome` is `finished`, `restart`, `quit`, or `dnf`.
Every player's `events` array starts with `start`. Checkpoints and respawns are
ordered by authoritative game duration, and the last event is `finish`, `quit`,
`restart`, or `dnf`. A finish event also contains its checkpoint information.
At equal durations the order is start, checkpoint, respawn, then terminal event.

MLFeed ranks and unavailable timing or checkpoint associations are serialized as
`null`, not zero or inferred values. `sessionBest.raceCheckpointTimesMs` and
`sessionBest.lapCheckpointTimesMs` are session snapshots from MLFeed and can be
partial before a complete race or lap. The matching `raceIsComplete` and
`lapIsComplete` flags indicate whether the expected number of waypoint times was
available.
When multiple respawns arrive in one MLFeed update, every authoritative respawn
time is retained; older respawns whose checkpoint or cumulative loss cannot be
reconstructed are emitted with those fields set to `null`.

## Run the test

1. Install Openplanet for Trackmania 2020 and enable **Developer** signature
   mode in Openplanet's settings. Unsigned local plugins only load in this mode.
2. Copy this repository folder into the Openplanet `Plugins` directory. Keep
   `info.toml` at the copied folder's root, for example:
   `OpenplanetNext/Plugins/ChugmaniaWebhooks/info.toml`. Alternatively, copy
   `dist/chugmania-webhooks-v0.1.0.op` directly into the `Plugins` directory.
3. Start Trackmania, then reload plugins from Openplanet's plugin manager. The
   log should contain `Race webhook capture loaded with MLFeed game timing`.
4. Start **Local > Arcade** or a local **Split Screen** race. Complete
   checkpoints and at least one lap with every controller/player.
5. Inspect the Openplanet log/console and filter for
   `[Chugmania Webhooks]`. Compare `playerIndex`, `login`, `name`, and
   `terminal` to identify each split-screen player.

Useful log records are `ATTEMPT_STARTED`, `FIRST_ACCELERATOR`, `CHECKPOINT`,
`RESPAWN`, `FINISH`, `ATTEMPT_ENDED`, and `WEBHOOK_DELIVERED`.

## Capture status

The original direct-game-API spike validated these values in Local Arcade and
local Split Screen:

- map metadata and medal targets;
- separate players with synthetic split-screen logins and terminal indices;
- per-player accelerator input;
- per-player checkpoint and finish transitions.

The new MLFeed-backed timing path still needs an in-game validation pass with
solo, 2-player split screen, and 4-player split screen logs.

Still missing or requiring validation:

- validation that MLFeed exposes every split-screen player in 2-player and
  4-player local modes;
- sector-specific metadata beyond the authoritative checkpoint index and time;
- validation of respawn checkpoint associations and time-lost values in solo
  and split-screen modes;
- proof that all supported local modes and multi-lap maps expose the same
  event behavior;
- direct detection of every menu-level quit path where the playground remains
  alive;
- persistent delivery across game or plugin shutdown (the retry queue is
  currently in memory);
- an account ID for synthetic split-screen users when MLFeed cannot resolve one
  (`accountId` is `null`).

The direct `CSmScriptPlayer` timing fields are not used. MLFeed injects a
ManiaScript feed and exposes each player's game `StartTime`, `CurrentRaceTimeRaw`,
`CpTimes`, respawn data, rankings, session bests, finish state, and identity.
Payload durations therefore use the game clock and report
`timingSource: "mlfeed_game_clock"`. UTC timestamps are derived by anchoring
those game durations to the local system UTC clock.

## Development notes

Package the plugin locally with the script for your platform. Both scripts read
the name and version from `info.toml` and create
`dist/chugmania-webhooks-v0.1.0.op` for the current metadata.

```powershell
.\scripts\build-op.ps1
```

```bash
bash ./scripts/build-op.sh
```

Pass an output directory as the first argument to place the artifact elsewhere.

- The plugin targets Trackmania 2020 (`TMNEXT`) APIs.
- The plugin requires the `MLHook` and `MLFeedRaceData` Openplanet plugins.
- Checkpoints and race durations come from MLFeed's ManiaScript data.
- Webhook requests are sent asynchronously from the plugin's main coroutine.
- For distribution outside Developer mode, package the files inside this folder
  as a zip, rename it to `.op`, and submit it for Openplanet signing.
