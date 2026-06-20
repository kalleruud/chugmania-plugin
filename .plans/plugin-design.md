# Trackmania Webhook Plugin

We're making a plugin which fires webhooks to a remote endpoint when events happen in Trackmaina games.

## Glossary

- A game: Any race event where one or more people race. A game is ended when the timer is reset. Can include multiple laps and respawns.

## Technical

- The plugin must support Trackmania Turbo and Trackmaina Next (2020)
    - Trackmaina Next depends on "MLHook", "MLFeedRaceData".
- The plugin must be configured with and endpoint ULR and Authentication token. Auth is done by setting the token in the "Authentication"-header. Also, it must be configuret with max retry count.
- The plugin must contain an `openai.yaml`-file which is always updated with the webhook contracts. The endpoint will generate types based on this file.
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

When any of these events happen in-game, a webhook should be fired. In split screen, multiple events can be emitted at once, especially the start event.

All events has:
    - Date-field with UTC datetime of when the event happend
    - The event type
    - Duration in milliseconds since start.
    - Game-specific player info
        - Player IDs (local and account)
        - Player index (For split screen or hot seat)
        - Total players
    - Game ID (Unique ID for all events related to a single round)
    - Source
        - Plugin name and version
        - Game name

- **start**: When a player starts a lap.
    - Player details
        - name, login, local id, account id
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
- **respawn**: When a player respawns whithout the timer resetting. Can restart to checkpoint or start line depending on the game mode.
    - Same as checkpoint event
    - Lost ms (Next only)
- **finish**: The player reaches the finish line, or finishes the last lap.
- **end**: When the player quits the game, or all players finish. This is ALWAYS the final event of a game and is only emitted once per game.
