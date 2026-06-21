# Trackmania Webhook Plugin

We're making a plugin which fires webhooks to a remote endpoint when events happen in Trackmaina games.

## Glossary

- **Game**: A complete race activity where one or more people race. In the
  currently supported scope, a game contains exactly one round and receives a
  new unique game ID when that round begins. Correlating multiple rounds as one
  game is out of scope.
- **Round**: A continuous timing session, from its first `start` event until its
  single final `end` event. A round ends when its timer stops. A timer restart is
  a new round and therefore a new game with a new game ID.
  - In Trackmania Turbo hot seat, each player's continuously timed attempt is a
    separate round and game with its own `gameId`, `start`, and `end`. The
    `start.players` roster still contains every configured hot-seat player, while
    player-scoped events use the currently active player's `playerIndex`.

## Technical

- The plugin must support Trackmania Turbo and Trackmaina Next (2020)
    - Trackmaina Next depends on "MLHook", "MLFeedRaceData".
- The plugin must be configured with an endpoint URL, authentication token, and
  maximum retry count. Each webhook request authenticates with the standard
  `Authorization: Bearer <token>` header. `openapi.yaml` must define and require
  the corresponding HTTP bearer security scheme.
    - Maximum retry count defaults to `3`, accepts values from `0` through `10`,
      and counts retries after the initial delivery attempt.
    - Event capture and delivery are disabled while the endpoint URL or token is
      empty, and no events are queued during that time. Non-empty endpoint URLs
      are not validated; request failures use the normal retry rules. Settings
      take effect immediately. If they become non-empty during an active round, the
      plugin may begin with a partial game and is not required to synthesize the
      missing `start` or earlier events.
    - Changing the endpoint URL or token does not clear queued events or cancel
      their delivery. Every delivery attempt, including a retry, uses the current
      endpoint URL and token, so existing queued events are sent to the new URL
      with the new credentials.
    - The plugin must emit correct UTC timestamps using Openplanet's built-in
      time APIs in both supported games: `Time::Stamp` for Unix epoch seconds,
      `Time::FormatStringUTC` for UTC formatting, and `Time::Now` to retain
      millisecond resolution between events. Do not use local-time formatting,
      an IANA timezone setting, or an external time API. Timestamp behavior must
      be tested explicitly in both Trackmania Turbo and Trackmania Next.
- The plugin must contain an `openapi.yaml` file that is always kept in sync
  with the webhook payload and response contracts. The endpoint will generate
  types from this file. It must document all delivery response codes, including
  the retryable response used when a valid event arrives outside an active
  receiver session and therefore cannot yet be registered.
    - Every event is sent with `POST` directly to the configured endpoint URL as
      a camelCase JSON object, without an outer wrapper object.
    - The request body is a `oneOf` union of all event schemas, discriminated by
      the `type` property with an explicit OpenAPI discriminator mapping.
    - Event and nested object schemas allow undeclared JSON properties for
      forward compatibility. The OpenAPI schemas must not set
      `additionalProperties: false`.
    - Unavailable game-specific values are omitted from JSON. Their properties
      are optional in `openapi.yaml`, with game/mode availability documented.
      Do not send `null`, empty-string, sentinel, or fabricated substitutes.
- The plugin only supports local solo and split screen. This includes:
    - TM Next local play and Campagin
    - TM Next Split screen, any mode (Time attack, Round, etc.)
    - TM Turbo Campagin, Hot seat, Arcade, Split Screen
    - TM Turbo Secret modes

## Strucutre

- Use `/clean-code` skill.
- Separate code into deep module-files called "services" They should have deep implementations and small interfaces.
- `src/Main.as` should be a thin orchestration layer, calling services as needed.
- `scripts/*` should contain scripts for mac/linux and windows to build `.op`-plugins.
- `.github/workflows/publish.yml` should use the scripts and create releases with plugin artifacts on merge into main.

## Events

When any of these events happen in-game, a webhook should be fired. In split
screen, multiple player-scoped events can occur in the same frame, but each
round still emits only one `start` and one `end`.

Webhook delivery must use a FIFO queue with at most one request in flight. The
event at the head of the queue is retried until it succeeds or exhausts the
configured retry count; only then may delivery continue with the next event.
Consequently, delivered events retain their occurrence order, normally with
`start` first and `end` last unless capture was enabled mid-round or an event was
dropped after retry exhaustion.

There is one global FIFO for the lifetime of the plugin process. When a new
round starts while events from an earlier round remain queued, its events are
appended after those earlier events. Starting a new game or changing `gameId`
does not clear the queue.

The delivery queue is memory-only. Pending and in-flight events are discarded
when the plugin or game process stops and are not restored on restart. Delivery
is therefore best-effort within the lifetime of the active plugin process.

The queue has a fixed, non-configurable capacity of 1,000 events. When it is
full, newly occurring events are dropped; existing queued events are retained so
the deliverable prefix remains in order. Every overflow drop must be written to
the local plugin log.

Delivery response handling:
    - Any `2xx` response is successful.
    - Network errors, `408`, `429`, `5xx`, and the explicitly documented
      "outside an active receiver session" response are retryable.
    - A retryable HTTP response's `Retry-After` header must be honored when
      present.
    - Without `Retry-After`, delay each retry by
      `currentRetryAttempt * 5 seconds`: 5 seconds before retry 1, 10 seconds
      before retry 2, and so on. No jitter is added.
    - Other `4xx` responses are permanent failures and are dropped immediately.
    - `503 Service Unavailable` with a typed `NO_ACTIVE_SESSION` error body means
      that a valid event arrived outside an active receiver session and could not
      be registered. This response is retryable and may include `Retry-After`.
      The status, error body, and header must be defined in `openapi.yaml`.

All events has:
    - `schemaVersion`: Required semantic-version string for the webhook payload
      contract, initially `1.0.0`. Retries reuse the captured version.
      - Increment MAJOR for removed or renamed fields, changed field meanings or
        types, or removed event variants.
      - Increment MINOR for new optional fields or new event variants.
      - Increment PATCH for documentation or OpenAPI corrections that do not
        change accepted JSON.
      - Schema versioning is independent of the plugin version reported in
        `source.pluginVersion`.
    - `occurredAt`: RFC 3339 UTC timestamp with millisecond precision, for
      example `2026-06-21T14:23:45.123Z`. It is captured when the event occurs
      and remains unchanged across delivery delays and retries.
    - The event type
    - Event ID (Globally unique. Retries of the same event reuse the original
      event ID.)
    - Sequence (Zero-based, contiguous occurrence order within a game. The
      `start` event has sequence `0`, and retries reuse the original sequence.)
    - Duration in milliseconds from the in-game race timer at the moment the
      event occurs. The value follows the in-game timer exactly, including its
      pause behavior. Delivery delays and retries must not change the captured
      value; `start` has a duration of `0`.
    - Game ID (Unique ID shared by all events from the first `start` through the
      single final `end` of one round)
    - Source
        - Plugin name and version
        - Game name

Player-scoped events (`first_throttle`, `checkpoint`, `lap`, `respawn`, and
`finish`) also contain:
    - `playerIndex`: Required zero-based player identity, stable for the game.
      Consumers join it to `start.players[playerIndex]`.
    - Optional player IDs (local and account), login, and name when exposed by
      the game. None of these platform identity fields is guaranteed.
    - `totalPlayers`: Required total number of players in the game. It remains
      constant across all player-scoped events for that game, including partial
      captures where the `start` event was not emitted.

- **start**: Emitted exactly once when a round begins. It contains the details of
  every player in the round, plus the map and mode details.
    - Player details for all players
        - Required zero-based player index
        - Optional name, login, local id, and account id
        - Players are ordered by contiguous index: for every array position `i`,
          `players[i].playerIndex == i`.
    - `totalPlayers`, equal to `players.length`
    - Map details
        - Name, UID, author, environment, type, medal times ms, total laps, isLaps, checkpoints per lap
    - Mode details
        - including settings for TM Next
- **first_throttle**: The first time the user presses the accelerator after lap start.
- **checkpoint**: When a player passes a checkpoint
    - checkpoint Index (Global index for all checkpoint, irrelevant of lap)
    - checkpoint lap Index (Index relative to lap, meaning the first checkpoint after start is 1)
    - Lap number
    - theoreticalDurationMs (Next only)
- **lap**: When a player passes start and a new lap starts. 
    - Same as checkpoint event, lap number should increase.
    - Checkpoint numbering excludes start and finish crossings. `lapNumber` is
      one-based. On checkpoint events, `checkpointLapIndex` is one-based and
      `checkpointIndex` is one-based and increases across intermediate
      checkpoints over all laps. A `lap` event reports the newly started lap,
      uses `checkpointLapIndex = 0`, and retains in `checkpointIndex` the total
      number of intermediate checkpoints passed so far.
- **respawn**: When a player respawns whithout the timer resetting. Can restart to checkpoint or start line depending on the game mode.
    - Same as checkpoint event
    - Lost ms (Next only)
    - Checkpoint fields identify the respawn destination, not the next
      checkpoint. A start-line respawn uses `checkpointIndex = 0` and
      `checkpointLapIndex = 0`; a checkpoint respawn uses the indices of the last
      validated checkpoint. `lapNumber` remains the current one-based lap.
    - A respawn to the start line is still only a `respawn` while the in-game
      timer continues. It does not emit another `start`, create a new `gameId`,
      or re-arm `first_throttle`. Only a timer restart creates a new game.
- **finish**: Emitted at most once per player when that player reaches the finish
  line or completes the final lap. A player may have no `finish` event if they
  quit, time out, or the mode only allows the winner to finish, as can happen in
  split-screen modes.
- **end**: When the round timer stops because the player quits, all players
  finish, or the mode otherwise completes the round. This is always the final
  event of a round, is emitted exactly once per round, and contains no player
  information.
    - End reason: `completed`, `restarted`, `aborted`, or `unknown`. The plugin
      must use `unknown` rather than infer a cause that cannot be determined
      reliably in both Trackmania Turbo and Trackmania Next.
