#if TURBO
class TurboGameAdapter : GameAdapter
{
    string lastMap;
    string diagnosticState;

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
        auto playground = app.CurrentPlayground;
        observation.local = playground.GameTerminals.Length > 0;
        if (!observation.local) {
            LogTurboState("local", "Turbo capture paused: no local game terminal was detected.");
            return observation;
        }
        if (lastMap != app.Challenge.IdName) lastMap = app.Challenge.IdName;
        @observation.map = ReadTurboMap(app.Challenge);
        @observation.mode = ReadTurboMode();
        uint firstRaceStartTime = 0;
        for (uint i = 0; i < playground.Players.Length; i++) {
            auto tmPlayer = cast<CTrackManiaPlayer>(playground.Players[i]);
            if (tmPlayer is null || tmPlayer.EnableOnlineMode) continue;
            bool racing = tmPlayer.RaceState == CTrackManiaPlayer::ERaceState::Running ||
                tmPlayer.RaceState == CTrackManiaPlayer::ERaceState::Finished;
            if (!racing) continue;
            PlayerSnapshot@ player = PlayerSnapshot();
            player.playerIndex = observation.players.Length;
            player.name = tmPlayer.Name;
            player.login = tmPlayer.Login;
            observation.players.InsertLast(player);
            PlayerObservation@ state = PlayerObservation();
            @state.player = player;
            state.durationMs = tmPlayer.CurRace is null ? 0 : uint(Math::Max(0, tmPlayer.CurRace.Time));
            state.throttle = tmPlayer.InputGasPedal;
            state.respawnCount = tmPlayer.NbRespawns;
            state.lapNumber = tmPlayer.CurLapIndex + 1;
            if (tmPlayer.CurRace !is null) state.checkpointIndex = tmPlayer.CurRace.Checkpoints.Length;
            if (tmPlayer.CurLap !is null) state.checkpointLapIndex = tmPlayer.CurLap.Checkpoints.Length;
            state.finished = tmPlayer.RaceState == CTrackManiaPlayer::ERaceState::Finished;
            observation.playerStates.InsertLast(state);
            if (observation.playerStates.Length == 1) firstRaceStartTime = tmPlayer.RaceStartTime;
        }
        observation.active = observation.local && !observation.playerStates.IsEmpty();
        if (observation.active) {
            observation.sessionKey = lastMap + ":" + firstRaceStartTime;
            LogTurboState("active", "Turbo capture detected an active local round with " + observation.players.Length + " player(s).");
        } else {
            LogTurboState("players", "Turbo capture waiting for a local player in a running race.");
        }
        return observation;
    }

    void LogTurboState(const string &in state, const string &in message)
    {
        if (state == diagnosticState) return;
        diagnosticState = state;
        print(message);
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
