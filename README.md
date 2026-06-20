# Chugmania Webhooks

An Openplanet plugin that captures local Trackmania 2020 or Trackmania Turbo
race attempts and sends one JSON webhook when an attempt ends.

The plugin watches every player in `CurrentPlayground.Players`, including local
split-screen players, and captures:

- player discovery and the controlled split-screen terminal index;
- first throttle input as an ordered race event;
- authoritative start, checkpoint, respawn, finish, restart, quit, and DNF events;
- map metadata and medal times;
- local format, game mode, and generic mode settings exposed by the rules API.

One `race.attempt.ended` request represents the complete attempt and always uses
the same `players[]` format for solo and split screen. Race durations and
checkpoint times come from MLFeed's ManiaScript-backed game clock in Trackmania
2020 and Turbo's native race results in Trackmania Turbo.

## Supported games

- **Trackmania 2020:** local solo and split-screen capture using MLHook and
  MLFeed: Race Data.
- **Trackmania Turbo:** local solo and split-screen capture using the native
  Turbo playground, player, and race-result APIs.

Turbo does not expose every mode rule or MLFeed-derived value. Those fields are
sent as `null`, including `mlFeedLapCount`, theoretical checkpoint times,
respawn checkpoint indexes, and generic mode settings. Turbo checkpoint and
finish times are native race-result values; lifecycle-only event times use a
monotonic clock anchored when the race is detected.

Online and party-mode capture are not currently guaranteed in Turbo.

## Build and install

Build both game packages on Windows:

```powershell
.\scripts\build-op.ps1 all
```

Or build one package with `trackmania` or `turbo`. The shell script accepts the
same target as its first argument:

```bash
./scripts/build-op.sh all
```

The resulting files are named with `-trackmania-` or `-turbo-`; install the one
matching the game. Unsigned development builds require Openplanet Developer
signature mode. Public distribution requires Openplanet review and signing.

## Webhook settings

Configure the plugin in **Openplanet > Settings > Chugmania Webhooks**:

- enable **Webhook > Enabled**;
- set **Webhook > Endpoint** to an HTTPS URL;
- set **Webhook > API key**;
- optionally change the retry count.

Requests use `POST`, `Content-Type: application/json`, and the API key is sent
in the `X-API-Key` header. Rate-limited requests honor numeric `Retry-After` and
`X-RateLimit-Reset` response headers, with a 30, 60, and 120 second fallback.
Other failed requests are retried after 1, 3, and 10 seconds by default.
