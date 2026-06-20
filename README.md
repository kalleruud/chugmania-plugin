# Chugmania Webhooks

An Openplanet plugin that captures local Trackmania race attempts and sends one
JSON webhook when an attempt ends.

The plugin watches every player in `CurrentPlayground.Players`, including local
split-screen players, and captures:

- player discovery and the controlled split-screen terminal index;
- first throttle input as an ordered race event;
- authoritative start, checkpoint, respawn, finish, restart, quit, and DNF events;
- map metadata and medal times;
- local format, game mode, and generic mode settings exposed by the rules API.

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
in the `X-API-Key` header. Rate-limited requests honor numeric `Retry-After` and
`X-RateLimit-Reset` response headers, with a 30, 60, and 120 second fallback.
Other failed requests are retried after 1, 3, and 10 seconds by default.
