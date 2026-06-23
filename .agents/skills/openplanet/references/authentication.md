# Authentication

Source: https://openplanet.dev/docs/reference/auth

Openplanet Auth is for proving a player's identity to your own backend.

## Setup

- Create the plugin on the Openplanet website.
- Enable authentication in the plugin admin page.
- Add `[meta] siteid = <numeric id>` to `info.toml`.
- Keep the plugin secret on the server only.

## Client Flow

- Call `Auth::GetToken()`.
- Wait for the task to finish from a yieldable context such as `Main()`.
- Send the returned token to your backend immediately; it is intentionally short-lived.

## Server Flow

- POST `application/x-www-form-urlencoded` to `https://openplanet.dev/api/auth/validate`.
- Send `token=<client_token>&secret=<plugin_secret>`.
- Reject any response containing `error`.
- Successful validation returns values such as `account_id`, `display_name`, and `token_time`.

## Guidance

- Exchange the short-lived Openplanet token for your own session token if persistent auth is needed.
- Use this for plugin-to-backend identity, not for general Nadeo API access. For in-plugin Nadeo requests, prefer the `NadeoServices` dependency.
