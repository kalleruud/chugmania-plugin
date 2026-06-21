# Chugmania Webhooks

An Openplanet plugin that emits ordered race events from supported local modes
in Trackmania Next (2020) and Trackmania Turbo.

The plugin sends a separate webhook for `start`, `first_throttle`,
`checkpoint`, `lap`, `respawn`, `finish`, and `end`. Every event carries a UUID,
an in-round sequence number, an RFC 3339 UTC timestamp, the in-game duration,
and stable game/source metadata. See [the webhook contract](docs/webhook-contract.md)
or [the OpenAPI description](openapi.yaml) for the complete payload model.

## Supported play

- Trackmania Next local play, campaign, and split screen
- Trackmania Turbo campaign, hot seat, arcade, split screen, and secret modes

Capture is conservative: it stays disabled unless a local playground can be
identified. Pending events share one memory-only FIFO across rounds.

## Timing precision

`durationMs` uses the in-game race clock, not wall-clock or webhook delivery
time. Its precision depends on how the game exposes each event:

- `first_throttle` and `respawn` are detected by polling game state once per
  rendered frame. Their true transition happened sometime after the previous
  poll and before the current poll, so `durationMs` can be late by up to roughly
  one frame. This also applies when throttle is held through the countdown:
  Turbo may not expose the positive input until the first frame after the timer
  starts. The plugin does not subtract an estimated frame delay because the
  exact transition time is unavailable and any correction would fabricate
  precision.
- `checkpoint`, `lap`, and `finish` are not stamped with the frame in which the
  plugin notices them. The game records their authoritative race-clock times;
  the plugin reads those stored values (`CurCheckpointRaceTime`/`CurRace.Time`
  in Turbo and MLFeed checkpoint/finish times in Trackmania Next). A later
  observation can delay webhook creation and delivery, but it does not change
  these events' `durationMs`.
- `start` is defined at race-clock `0`. `end` uses the race clock when the end
  condition is observed.

## Configuration

Open **Openplanet > Settings > Chugmania Webhooks > Webhook** and set:

- **Endpoint URL**: destination for HTTP POST requests
- **Authentication token**: optional secret sent as `Authorization: Bearer <token>`
- **Maximum retry count**: retries after the initial attempt, from 0 to 10

Capture and delivery are disabled while the URL is empty. Requests use
`Content-Type: application/json; charset=utf-8` and an `event_type` header that
matches the payload's `type`. When the token is empty, the request is sent
without authentication. The token is masked and never logged.

## Build

Build both packages on Windows:

```powershell
.\scripts\build-op.ps1 all
```

Or on a Unix-like shell:

```bash
./scripts/build-op.sh all
```

The output files are `dist/chugmania-webhooks-next.op` and
`dist/chugmania-webhooks-turbo.op`. Each archive contains the matching manifest
as `info.toml` and the shared `src` tree.

Unsigned builds require Openplanet Developer signature mode. Public
distribution requires the normal Openplanet review and signing process.
