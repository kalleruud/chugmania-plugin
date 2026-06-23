# Trackmania Web Services

Source: https://webservices.openplanet.dev/

This documentation is the Openplanet community's unofficial reference for Trackmania (2020) web services. It is separate from the in-game Openplanet runtime APIs.

## Main Domains

- `Core`: account and master-service style functionality plus auth plumbing for other APIs.
- `Live`: live content such as leaderboards, campaigns, clubs, rooms, and Track of the Day data.
- `Meet`: competition and matchmaking infrastructure. Older Competition, Matchmaking, and Club domains were merged into Meet in July 2023.

## Authentication Paths

- The docs provide two main game-API authentication paths: service account and dedicated server account.
- Token handling is documented separately under the token usage guide.
- For Openplanet plugins, do not hand-roll game API authentication inside the plugin; use `NadeoServices` instead.

## OAuth

- The Trackmania OAuth docs are separate from the primary game APIs and use different tokens and flows.
- OAuth is mainly for external applications or identity-verification flows, not as a drop-in replacement for normal game API tokens.
- Supported flows are the Trackmania OAuth flows documented under `/oauth/...`; they are not interchangeable with the main Web Services auth tokens.

## Responsible Usage

- Nadeo/Ubisoft can ban accounts or IPs for abusive request patterns.
- The docs note there are no official rate limits, but past guidance suggested roughly two requests per second for short bursts.
- Always send a meaningful `User-Agent` that identifies your project and contact method.

## Helpful Links

- Auth guide: `https://webservices.openplanet.dev/auth`
- OAuth introduction: `https://webservices.openplanet.dev/oauth/summary`
- Status page: `https://trackmania-status.cdn.ubi.com/status.html`
- Status JSON: `https://trackmania-status.cdn.ubi.com/status.json`
