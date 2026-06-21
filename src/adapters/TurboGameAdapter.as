#if TURBO
class TurboGameAdapter : GameAdapter
{
    string lastMap;
    string diagnosticState;
    string activeSessionKey;
    bool startArmed;
    bool roundCompleted;
    string pendingEndReason;

    GameObservation@ Observe()
    {
        GameObservation@ observation = GameObservation();
        CGameManiaPlanet@ app = cast<CGameManiaPlanet>(GetApp());
        if (app is null) {
            LogTurboState("app", "Turbo capture waiting for the game application.");
            return observation;
        }
        if (app.CurrentPlayground is null) {
            LogTurboState("playground", "Turbo capture waiting for a playground.");
            return observation;
        }
        if (app.Challenge is null) {
            LogTurboState("map", "Turbo capture waiting for a map.");
            return observation;
        }
        if (app.PlaygroundScript is null || app.PlaygroundScript.UIManager is null) {
            LogTurboState("script", "Turbo capture waiting for the playground script.");
            return observation;
        }
        auto playground = app.CurrentPlayground;
        observation.local = playground.GameTerminals.Length > 0;
        if (!observation.local) {
            LogTurboState("local", "Turbo capture paused: no local game terminal was detected.");
            return observation;
        }
        if (lastMap != app.Challenge.IdName) {
            lastMap = app.Challenge.IdName;
            activeSessionKey = "";
            startArmed = false;
            roundCompleted = false;
            pendingEndReason = "";
        }
        @observation.map = ReadTurboMap(app.Challenge);
        @observation.mode = ReadTurboMode();
        auto uiConfig = app.PlaygroundScript.UIManager.LocalPlayerConfig;
        bool playingSequence = uiConfig !is null &&
            (uiConfig.UISequence == CGamePlaygroundUIConfig::EUISequence::Playing ||
            uiConfig.UISequence == CGamePlaygroundUIConfig::EUISequence::EndRound);
        for (uint i = 0; i < playground.Players.Length; i++) {
            auto tmPlayer = cast<CTrackManiaPlayer>(playground.Players[i]);
            if (tmPlayer is null || tmPlayer.EnableOnlineMode || tmPlayer.AutoPilotEnabled) continue;
            if (tmPlayer.RaceState == CTrackManiaPlayer::ERaceState::BeforeStart) {
                if (activeSessionKey.Length > 0) {
                    pendingEndReason = roundCompleted ? "completed" : "restarted";
                }
                startArmed = true;
                activeSessionKey = "";
                continue;
            }
            if (tmPlayer.RaceState == CTrackManiaPlayer::ERaceState::Eliminated) {
                if (activeSessionKey.Length > 0) pendingEndReason = "aborted";
                continue;
            }
            bool racing = tmPlayer.RaceState == CTrackManiaPlayer::ERaceState::Running ||
                tmPlayer.RaceState == CTrackManiaPlayer::ERaceState::Finished;
            if (!racing || !playingSequence || tmPlayer.RaceStartTime == 0) continue;
            string candidateSessionKey = lastMap + ":" + tmPlayer.RaceStartTime;
            if (activeSessionKey.Length == 0) {
                if (!startArmed) continue;
                activeSessionKey = candidateSessionKey;
                startArmed = false;
                roundCompleted = false;
                pendingEndReason = "";
            }
            if (candidateSessionKey != activeSessionKey) continue;
            PlayerSnapshot@ player = PlayerSnapshot();
            player.playerIndex = observation.players.Length;
            player.name = tmPlayer.Name;
            player.login = tmPlayer.Login;
            observation.players.InsertLast(player);
            PlayerObservation@ state = PlayerObservation();
            @state.player = player;
            state.durationMs = app.PlaygroundScript.Now > tmPlayer.RaceStartTime
                ? app.PlaygroundScript.Now - tmPlayer.RaceStartTime
                : 0;
            state.throttle = tmPlayer.InputGasPedal;
            state.respawnCount = tmPlayer.NbRespawns;
            state.lapNumber = tmPlayer.CurLapIndex + 1;
            if (tmPlayer.CurRace !is null) state.checkpointIndex = tmPlayer.CurRace.Checkpoints.Length;
            if (tmPlayer.CurLap !is null) state.checkpointLapIndex = tmPlayer.CurLap.Checkpoints.Length;
            state.finished = tmPlayer.RaceState == CTrackManiaPlayer::ERaceState::Finished;
            roundCompleted = roundCompleted || state.finished;
            observation.playerStates.InsertLast(state);
        }
        observation.active = observation.local && !observation.playerStates.IsEmpty();
        if (observation.active) {
            observation.sessionKey = activeSessionKey;
            LogTurboState("active", "Turbo capture detected an active local round with " + observation.players.Length + " player(s).");
        } else {
            observation.endReason = pendingEndReason.Length > 0
                ? pendingEndReason
                : (roundCompleted ? "completed" : "unknown");
            pendingEndReason = "";
            LogTurboState("players", "Turbo capture armed and waiting for the race timer to start.");
        }
        return observation;
    }

    void LogTurboState(const string &in state, const string &in message)
    {
        if (state == diagnosticState) return;
        diagnosticState = state;
        print("[detect] " + message);
    }
}

MapSnapshot@ ReadTurboMap(CGameCtnChallenge@ challenge)
{
    MapSnapshot@ map = MapSnapshot();
    map.name = challenge.MapName;
    map.uid = challenge.IdName;
    map.author = challenge.AuthorNickName;
    map.mapType = challenge.MapType;
    map.isLaps = challenge.TMObjective_IsLapRace;
    map.authorTime = challenge.TMObjective_AuthorTime;
    map.goldTime = challenge.TMObjective_GoldTime;
    map.silverTime = challenge.TMObjective_SilverTime;
    map.bronzeTime = challenge.TMObjective_BronzeTime;
    return map;
}

ModeSnapshot@ ReadTurboMode()
{
    ModeSnapshot@ mode = ModeSnapshot();
    mode.name = "Local play";
    return mode;
}
#endif
