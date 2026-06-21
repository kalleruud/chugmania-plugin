#if TURBO
class TurboGameAdapter : GameAdapter
{
    string lastMap;

    GameObservation@ Observe()
    {
        GameObservation@ observation = GameObservation();
        CGameManiaPlanet@ app = cast<CGameManiaPlanet>(GetApp());
        if (app is null || app.CurrentPlayground is null || app.RootMap is null) return observation;
        auto playground = app.CurrentPlayground;
        observation.local = playground.GameTerminals.Length > 0;
        if (lastMap != app.RootMap.IdName) lastMap = app.RootMap.IdName;
        @observation.map = ReadTurboMap(app);
        @observation.mode = ReadTurboMode(playground);
        for (uint i = 0; i < playground.Players.Length; i++) {
            auto tmPlayer = cast<CTrackManiaPlayer>(playground.Players[i]);
            if (tmPlayer is null || tmPlayer.EnableOnlineMode) continue;
            PlayerSnapshot@ player = PlayerSnapshot();
            player.playerIndex = observation.players.Length;
            player.name = tmPlayer.Name;
            player.login = tmPlayer.Login;
            observation.players.InsertLast(player);
            PlayerObservation@ state = PlayerObservation();
            @state.player = player;
            state.durationMs = playground.GameTime > tmPlayer.RaceStartTime
                ? playground.GameTime - tmPlayer.RaceStartTime
                : 0;
            state.throttle = tmPlayer.InputGasPedal;
            state.respawnCount = tmPlayer.NbRespawns;
            state.lapNumber = tmPlayer.CurLapIndex + 1;
            if (tmPlayer.CurRace !is null) state.checkpointIndex = tmPlayer.CurRace.Checkpoints.Length;
            if (tmPlayer.CurLap !is null) state.checkpointLapIndex = tmPlayer.CurLap.Checkpoints.Length;
            state.finished = tmPlayer.RaceState == CTrackManiaPlayer::ERaceState::Finished;
            observation.playerStates.InsertLast(state);
        }
        observation.active = observation.local && !observation.playerStates.IsEmpty();
        if (observation.active) {
            auto firstPlayer = cast<CTrackManiaPlayer>(playground.Players[0]);
            observation.sessionKey = lastMap + ":" + firstPlayer.RaceStartTime;
        }
        return observation;
    }
}

MapSnapshot@ ReadTurboMap(CGameManiaPlanet@ app)
{
    MapSnapshot@ map = MapSnapshot();
    map.name = app.RootMap.MapName;
    map.uid = app.RootMap.IdName;
    map.author = app.RootMap.AuthorNickName;
    map.mapType = app.RootMap.MapType;
    map.isLaps = app.RootMap.IsLapRace;
    map.authorTime = app.RootMap.TMObjective_AuthorTime;
    map.goldTime = app.RootMap.TMObjective_GoldTime;
    map.silverTime = app.RootMap.TMObjective_SilverTime;
    map.bronzeTime = app.RootMap.TMObjective_BronzeTime;
    return map;
}

ModeSnapshot@ ReadTurboMode(CGameManiaPlanetPlayground@ playground)
{
    ModeSnapshot@ mode = ModeSnapshot();
    mode.name = "Local play";
    return mode;
}
#endif
