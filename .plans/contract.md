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

| Field           | Type                 | Rules                                                    |
| --------------- | -------------------- | -------------------------------------------------------- |
| `schemaVersion` | string               | Required SemVer; initially `1.0.0`                       |
| `type`          | string               | Required event discriminator                             |
| `eventId`       | UUID string          | Globally unique UUID v4; immutable across retries        |
| `sequence`      | non-negative integer | Contiguous capture order within `gameId`                 |
| `occurredAt`    | RFC 3339 string      | UTC with millisecond precision; immutable across retries |
| `durationMs`    | non-negative integer | In-game race timer when the event occurred               |
| `gameId`        | UUID string          | UUID v4 shared by all events in one round                |
| `source`        | Source               | Required producer metadata                               |

`start.sequence` is `0` for complete captures. When capture begins mid-round,
the first captured event also uses sequence `0`, even though no start event was
emitted.

### Source

| Field           | Type   | Rules                                 |
| --------------- | ------ | ------------------------------------- |
| `pluginName`    | string | Required; `Chugmania Webhooks`        |
| `pluginVersion` | string | Required plugin SemVer                |
| `game`          | enum   | `trackmaniaTurbo` or `trackmaniaNext` |

## Player Models

### Player

| Field         | Type                 | Rules                                        |
| ------------- | -------------------- | -------------------------------------------- |
| `playerIndex` | non-negative integer | Required, zero-based, stable within the game |
| `name`        | string               | Optional                                     |
| `login`       | string               | Optional                                     |
| `localId`     | string               | Optional                                     |
| `accountId`   | string               | Optional                                     |

`start.players` is ordered by contiguous index, so
`players[i].playerIndex == i`. Its length equals `totalPlayers`.

### Player Event Fields

Every `first_throttle`, `checkpoint`, `lap`, `respawn`, and `finish` event adds:

| Field          | Type                 | Rules                                           |
| -------------- | -------------------- | ----------------------------------------------- |
| `playerIndex`  | non-negative integer | Required; joins to `start.players[playerIndex]` |
| `totalPlayers` | positive integer     | Required and constant within the game           |
| `name`         | string               | Optional                                        |
| `login`        | string               | Optional                                        |
| `localId`      | string               | Optional                                        |
| `accountId`    | string               | Optional                                        |

## Start Models

### Map

| Field               | Type                 | Rules                                           |
| ------------------- | -------------------- | ----------------------------------------------- |
| `name`              | string               | Required                                        |
| `uid`               | string               | Optional                                        |
| `author`            | string               | Optional                                        |
| `environment`       | string               | Optional                                        |
| `type`              | string               | Optional                                        |
| `medalTimesMs`      | MedalTimes           | Optional                                        |
| `isLaps`            | boolean              | Required                                        |
| `totalLaps`         | positive integer     | Optional; omitted when unknown or not lap-based |
| `checkpointsPerLap` | non-negative integer | Optional; excludes start and finish             |

### MedalTimes

All medal properties are optional non-negative integer millisecond times:
`author`, `gold`, `silver`, and `bronze`.

### Mode

| Field      | Type   | Rules                                                       |
| ---------- | ------ | ----------------------------------------------------------- |
| `name`     | string | Required                                                    |
| `type`     | string | Optional                                                    |
| `settings` | object | Optional available primitive settings, using camelCase keys |

## Event Shapes

### `start`

Emitted exactly once when a fully captured round begins.

| Additional field | Type             | Rules                               |
| ---------------- | ---------------- | ----------------------------------- |
| `players`        | Player[]         | Required, ordered contiguous roster |
| `totalPlayers`   | positive integer | Required; equals `players.length`   |
| `map`            | Map              | Required                            |
| `mode`           | Mode             | Required                            |

### `first_throttle`

Contains common and player event fields only. It is emitted at most once per
player per game and is never re-armed.

### `checkpoint`

| Additional field        | Type                 | Rules                                            |
| ----------------------- | -------------------- | ------------------------------------------------ |
| `checkpointIndex`       | positive integer     | Global intermediate-checkpoint index across laps |
| `checkpointLapIndex`    | positive integer     | Intermediate-checkpoint index within the lap     |
| `lapNumber`             | positive integer     | One-based current lap                            |
| `theoreticalDurationMs` | non-negative integer | Optional, Next-only dependency value, unchanged  |

Start and finish crossings are excluded from checkpoint numbering.

### `lap`

| Additional field     | Type                 | Rules                                        |
| -------------------- | -------------------- | -------------------------------------------- |
| `checkpointIndex`    | non-negative integer | Total intermediate checkpoints passed so far |
| `checkpointLapIndex` | integer              | Required and always `0`                      |
| `lapNumber`          | positive integer     | Newly started one-based lap                  |

No lap event is emitted for the final finish crossing.

### `respawn`

| Additional field     | Type                 | Rules                                           |
| -------------------- | -------------------- | ----------------------------------------------- |
| `checkpointIndex`    | non-negative integer | Global index of respawn destination             |
| `checkpointLapIndex` | non-negative integer | Lap-relative index of respawn destination       |
| `lapNumber`          | positive integer     | Current one-based lap                           |
| `lostMs`             | non-negative integer | Optional, Next-only dependency value, unchanged |

A start-line destination uses both checkpoint indices as `0`. A checkpoint
destination uses the indices of the last validated checkpoint.

### `finish`

Contains common and player event fields only. `durationMs` is the player's
finish time. It is emitted at most once per player per game.

### `end`

Contains common fields and `endReason`. It contains no player fields.

| Additional field | Type | Rules                                             |
| ---------------- | ---- | ------------------------------------------------- |
| `endReason`      | enum | `completed`, `restarted`, `aborted`, or `unknown` |

## Responses

Any `2xx` response is successful; the plugin ignores its body. The documented
success responses are `200 OK` and `204 No Content`.

Errors use this forward-compatible shape:

| Field     | Type   | Rules                          |
| --------- | ------ | ------------------------------ |
| `code`    | string | Required machine-readable code |
| `message` | string | Optional human-readable detail |

`503 Service Unavailable` with `code: "NO_ACTIVE_SESSION"` means the event was
valid but arrived outside an active receiver session. It is retryable and may
include `Retry-After` as integer seconds or an HTTP date.

The plugin retries network errors, `408`, `429`, and all `5xx` responses. Other
`4xx` and all `3xx` responses are permanent failures.
