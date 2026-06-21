# Webhook Contract

This document defines the human-readable webhook model for schema version
`1.0.0`. `openapi.yaml` is the machine-readable authority and must remain
synchronized with this document.

## Transport

The plugin sends each event directly to the configured URL:

```http
POST /
Authorization: Bearer <token>
Content-Type: application/json; charset=utf-8
```

There is no outer payload wrapper. The `type` property discriminates the event
shape. Object schemas permit undeclared properties for forward compatibility.
Unavailable optional values are omitted, never represented by `null`, empty
strings, sentinels, or fabricated values.

## Common Event

Every event contains:

| Field           | Type                 | Description                             | Rules                                                    |
| --------------- | -------------------- | --------------------------------------- | -------------------------------------------------------- |
| `schemaVersion` | string               | Version of the webhook payload schema   | Required SemVer; initially `1.0.0`                       |
| `type`          | string               | Kind of event represented               | Required event discriminator                             |
| `eventId`       | UUID string          | Unique identity of the captured event   | Globally unique UUID v4; immutable across retries        |
| `sequence`      | non-negative integer | Event position within the round         | Contiguous capture order within `gameId`                 |
| `occurredAt`    | RFC 3339 string      | Wall-clock time of capture              | UTC with millisecond precision; immutable across retries |
| `durationMs`    | non-negative integer | Race-clock time of capture              | In-game race timer when the event occurred               |
| `gameId`        | UUID string          | Identity used to correlate round events | UUID v4 shared by all events in one round                |
| `source`        | Source               | Metadata describing the event producer  | Required producer metadata                               |

`start.sequence` is `0` for complete captures. When capture begins mid-round,
the first captured event also uses sequence `0`, even though no start event was
emitted.

### Source

| Field           | Type   | Description                         | Rules                                 |
| --------------- | ------ | ----------------------------------- | ------------------------------------- |
| `pluginName`    | string | Name of the producing plugin        | Required; `Chugmania Webhooks`        |
| `pluginVersion` | string | Version of the producing plugin     | Required plugin SemVer                |
| `game`          | enum   | Trackmania game producing the event | `trackmaniaTurbo` or `trackmaniaNext` |

## Player Models

### Player

| Field         | Type                 | Description                          | Rules                                        |
| ------------- | -------------------- | ------------------------------------ | -------------------------------------------- |
| `playerIndex` | non-negative integer | Position of the player in the roster | Required, zero-based, stable within the game |
| `name`        | string               | Display name of the player           | Optional                                     |
| `login`       | string               | Login identifier of the player       | Optional                                     |
| `localId`     | string               | Local identifier of the player       | Optional                                     |
| `accountId`   | string               | Account identifier of the player     | Optional                                     |

`start.players` is ordered by contiguous index, so
`players[i].playerIndex == i`. Its length equals `totalPlayers`.

### Player Event Fields

Every `first_throttle`, `checkpoint`, `lap`, `respawn`, and `finish` event adds:

| Field          | Type                 | Description                          | Rules                                           |
| -------------- | -------------------- | ------------------------------------ | ----------------------------------------------- |
| `playerIndex`  | non-negative integer | Position of the player in the roster | Required; joins to `start.players[playerIndex]` |
| `totalPlayers` | positive integer     | Number of players in the round       | Required and constant within the game           |
| `name`         | string               | Display name of the player           | Optional                                        |
| `login`        | string               | Login identifier of the player       | Optional                                        |
| `localId`      | string               | Local identifier of the player       | Optional                                        |
| `accountId`    | string               | Account identifier of the player     | Optional                                        |

## Start Models

### Map

| Field               | Type                 | Description                                | Rules                                           |
| ------------------- | -------------------- | ------------------------------------------ | ----------------------------------------------- |
| `name`              | string               | Display name of the map                    | Required                                        |
| `uid`               | string               | Unique identifier of the map               | Optional                                        |
| `author`            | string               | Creator of the map                         | Optional                                        |
| `environment`       | string               | Environment or setting used by the map     | Optional                                        |
| `type`              | string               | Map type reported by the game              | Optional                                        |
| `medalTimesMs`      | MedalTimes           | Target medal times in milliseconds         | Optional                                        |
| `isLaps`            | boolean              | Whether the map uses multiple laps         | Required                                        |
| `totalLaps`         | positive integer     | Number of laps required to finish          | Optional; omitted when unknown or not lap-based |
| `checkpointsPerLap` | non-negative integer | Number of intermediate checkpoints per lap | Optional; excludes start and finish             |

### MedalTimes

All medal properties are optional non-negative integer millisecond times:
`author`, `gold`, `silver`, and `bronze`.

### Mode

| Field      | Type   | Description                         | Rules                                                       |
| ---------- | ------ | ----------------------------------- | ----------------------------------------------------------- |
| `name`     | string | Display name of the game mode       | Required                                                    |
| `type`     | string | Game-reported mode type             | Optional                                                    |
| `settings` | object | Available configuration of the mode | Optional available primitive settings, using camelCase keys |

## Event Shapes

The examples form one Trackmania Turbo round and use fields supported by both
games. For Trackmania Next, `source.game` is `trackmaniaNext`.

### `start`

Emitted exactly once when a fully captured round begins.

| Additional field | Type             | Description                        | Rules                               |
| ---------------- | ---------------- | ---------------------------------- | ----------------------------------- |
| `players`        | Player[]         | Players participating in the round | Required, ordered contiguous roster |
| `totalPlayers`   | positive integer | Number of participating players    | Required; equals `players.length`   |
| `map`            | Map              | Map played during the round        | Required                            |
| `mode`           | Mode             | Game mode used during the round    | Required                            |

```json
{
  "schemaVersion": "1.0.0",
  "type": "start",
  "eventId": "4fda6f13-e003-47f6-a5df-32ec4e826749",
  "sequence": 0,
  "occurredAt": "2026-06-21T12:34:56.789Z",
  "durationMs": 0,
  "gameId": "b979cde4-2ef3-49b6-9ae8-c8231ba701f2",
  "source": {
    "pluginName": "Chugmania Webhooks",
    "pluginVersion": "0.1.0",
    "game": "trackmaniaTurbo"
  },
  "players": [
    {
      "playerIndex": 0,
      "name": "Player One"
    }
  ],
  "totalPlayers": 1,
  "map": {
    "name": "Example Map",
    "isLaps": true,
    "totalLaps": 2,
    "checkpointsPerLap": 5
  },
  "mode": {
    "name": "Time Attack"
  }
}
```

### `first_throttle`

Contains common and player event fields only. It is emitted at most once per
player per game and is never re-armed.

```json
{
  "schemaVersion": "1.0.0",
  "type": "first_throttle",
  "eventId": "652d3844-9e57-4528-94e4-1bfe20c0b194",
  "sequence": 1,
  "occurredAt": "2026-06-21T12:34:56.914Z",
  "durationMs": 125,
  "gameId": "b979cde4-2ef3-49b6-9ae8-c8231ba701f2",
  "source": {
    "pluginName": "Chugmania Webhooks",
    "pluginVersion": "0.1.0",
    "game": "trackmaniaTurbo"
  },
  "player": {
    "playerIndex": 0,
    "name": "Player One"
  },
  "totalPlayers": 1
}
```

### `checkpoint`

| Additional field        | Type                 | Description                               | Rules                                            |
| ----------------------- | -------------------- | ----------------------------------------- | ------------------------------------------------ |
| `checkpointIndex`       | positive integer     | Overall checkpoint reached by the player  | Global intermediate-checkpoint index across laps |
| `checkpointLapIndex`    | positive integer     | Checkpoint reached within the current lap | Intermediate-checkpoint index within the lap     |
| `lapNumber`             | positive integer     | Lap containing the checkpoint             | One-based current lap                            |
| `theoreticalDurationMs` | non-negative integer | Dependency-provided theoretical race time | Optional, Next-only dependency value, unchanged  |

Start and finish crossings are excluded from checkpoint numbering.

```json
{
  "schemaVersion": "1.0.0",
  "type": "checkpoint",
  "eventId": "a86f8d3d-7a36-4ec4-a9c9-60c69932bfd1",
  "sequence": 2,
  "occurredAt": "2026-06-21T12:35:06.789Z",
  "durationMs": 10000,
  "gameId": "b979cde4-2ef3-49b6-9ae8-c8231ba701f2",
  "source": {
    "pluginName": "Chugmania Webhooks",
    "pluginVersion": "0.1.0",
    "game": "trackmaniaTurbo"
  },
  "player": {
    "playerIndex": 0,
    "name": "Player One"
  },
  "totalPlayers": 1,
  "checkpointIndex": 1,
  "checkpointLapIndex": 1,
  "lapNumber": 1
}
```

### `lap`

| Additional field     | Type                 | Description                               | Rules                                        |
| -------------------- | -------------------- | ----------------------------------------- | -------------------------------------------- |
| `checkpointIndex`    | non-negative integer | Overall checkpoint progress of the player | Total intermediate checkpoints passed so far |
| `checkpointLapIndex` | integer              | Checkpoint position at the new lap start  | Required and always `0`                      |
| `lapNumber`          | positive integer     | Lap entered by the player                 | Newly started one-based lap                  |

No lap event is emitted for the final finish crossing.

```json
{
  "schemaVersion": "1.0.0",
  "type": "lap",
  "eventId": "ae91d8c5-c579-4360-8560-6c23aca43e7e",
  "sequence": 3,
  "occurredAt": "2026-06-21T12:35:46.789Z",
  "durationMs": 50000,
  "gameId": "b979cde4-2ef3-49b6-9ae8-c8231ba701f2",
  "source": {
    "pluginName": "Chugmania Webhooks",
    "pluginVersion": "0.1.0",
    "game": "trackmaniaTurbo"
  },
  "player": {
    "playerIndex": 0,
    "name": "Player One"
  },
  "totalPlayers": 1,
  "checkpointIndex": 5,
  "checkpointLapIndex": 0,
  "lapNumber": 2
}
```

### `respawn`

| Additional field     | Type                 | Description                                | Rules                                           |
| -------------------- | -------------------- | ------------------------------------------ | ----------------------------------------------- |
| `checkpointIndex`    | non-negative integer | Overall checkpoint used as the spawn point | Global index of respawn destination             |
| `checkpointLapIndex` | non-negative integer | Lap checkpoint used as the spawn point     | Lap-relative index of respawn destination       |
| `lapNumber`          | positive integer     | Lap in which the player respawned          | Current one-based lap                           |
| `lostMs`             | non-negative integer | Dependency-provided time lost on respawn   | Optional, Next-only dependency value, unchanged |

A start-line destination uses both checkpoint indices as `0`. A checkpoint
destination uses the indices of the last validated checkpoint.

```json
{
  "schemaVersion": "1.0.0",
  "type": "respawn",
  "eventId": "732780b9-ce63-4880-a17e-253ce4c4b36f",
  "sequence": 4,
  "occurredAt": "2026-06-21T12:35:58.789Z",
  "durationMs": 62000,
  "gameId": "b979cde4-2ef3-49b6-9ae8-c8231ba701f2",
  "source": {
    "pluginName": "Chugmania Webhooks",
    "pluginVersion": "0.1.0",
    "game": "trackmaniaTurbo"
  },
  "player": {
    "playerIndex": 0,
    "name": "Player One"
  },
  "totalPlayers": 1,
  "checkpointIndex": 6,
  "checkpointLapIndex": 1,
  "lapNumber": 2
}
```

### `finish`

Contains common and player event fields only. `durationMs` is the player's
finish time. It is emitted at most once per player per game.

```json
{
  "schemaVersion": "1.0.0",
  "type": "finish",
  "eventId": "50f83623-6649-4865-ab71-10407faf5030",
  "sequence": 5,
  "occurredAt": "2026-06-21T12:36:46.789Z",
  "durationMs": 110000,
  "gameId": "b979cde4-2ef3-49b6-9ae8-c8231ba701f2",
  "source": {
    "pluginName": "Chugmania Webhooks",
    "pluginVersion": "0.1.0",
    "game": "trackmaniaTurbo"
  },
  "player": {
    "playerIndex": 0,
    "name": "Player One"
  },
  "totalPlayers": 1
}
```

### `end`

Contains common fields and `endReason`. It contains no player fields.

| Additional field | Type | Description                     | Rules                                             |
| ---------------- | ---- | ------------------------------- | ------------------------------------------------- |
| `endReason`      | enum | Reason the captured round ended | `completed`, `restarted`, `aborted`, or `unknown` |

```json
{
  "schemaVersion": "1.0.0",
  "type": "end",
  "eventId": "b0985c12-77ac-4f81-8f69-19e89f937df1",
  "sequence": 6,
  "occurredAt": "2026-06-21T12:36:46.789Z",
  "durationMs": 110000,
  "gameId": "b979cde4-2ef3-49b6-9ae8-c8231ba701f2",
  "source": {
    "pluginName": "Chugmania Webhooks",
    "pluginVersion": "0.1.0",
    "game": "trackmaniaTurbo"
  },
  "endReason": "completed"
}
```

## Responses

Any `2xx` response is successful; the plugin ignores its body. The documented
success responses are `200 OK` and `204 No Content`.

Errors use this forward-compatible shape:

| Field     | Type   | Description                       | Rules                          |
| --------- | ------ | --------------------------------- | ------------------------------ |
| `code`    | string | Identifier for the response error | Required machine-readable code |
| `message` | string | Explanation of the response error | Optional human-readable detail |

`503 Service Unavailable` with `code: "NO_ACTIVE_SESSION"` means the event was
valid but arrived outside an active receiver session. It is retryable and may
include `Retry-After` as integer seconds or an HTTP date.

The plugin retries network errors, `408`, `429`, and all `5xx` responses. Other
`4xx` and all `3xx` responses are permanent failures.
