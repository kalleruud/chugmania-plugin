# NadeoServices

Source: https://openplanet.dev/docs/reference/nadeoservices

`NadeoServices` is the preferred Openplanet dependency for calling Nadeo web APIs from inside plugins.

## Setup

- Add `[script] dependencies = [ "NadeoServices" ]` to `info.toml`.
- In a yieldable context, call `NadeoServices::AddAudience(...)` and wait until `NadeoServices::IsAuthenticated(...)` returns true.

## Audiences

- `NadeoLiveServices`: Live and Meet APIs.
- `NadeoServices`: Core API.

## Useful Helpers

- `NadeoServices::GetAccountID()`
- `NadeoServices::BaseURLCore()`
- `NadeoServices::BaseURLLive()`
- `NadeoServices::BaseURLMeet()`
- Authenticated request helpers such as `Request`, `Get`, `Post`, `Put`, `Delete`, and `Patch`
- Display-name and account-ID conversion helpers

## Guidance

- Do not reimplement in-plugin Nadeo auth when `NadeoServices` can do it safely for you.
- This is the right tool for Openplanet plugins in both Trackmania Next and Trackmania Turbo when the dependency supports the needed endpoint flow.
