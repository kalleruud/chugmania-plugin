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
