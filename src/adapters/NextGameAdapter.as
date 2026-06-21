#if TMNEXT
class NextGameAdapter : GameAdapter
{
    uint sessionNumber;
    uint previousDuration;

    GameObservation@ Observe()
    {
        GameObservation@ observation = GameObservation();
        CTrackMania@ app = cast<CTrackMania>(GetApp());
        if (app is null || app.CurrentPlayground is null || app.RootMap is null) return observation;
        auto playground = app.CurrentPlayground;
        observation.local = app.Network !is null && app.Network.PlaygroundClientScriptAPI !is null &&
            app.Network.PlaygroundClientScriptAPI.IsServerOrSolo;
        @observation.map = ReadNextMap(app);
        @observation.mode = ReadNextMode(playground);
        auto race = MLFeed::GetRaceData_V4();
        for (uint i = 0; i < playground.Players.Length; i++) {
            auto smPlayer = cast<CSmPlayer>(playground.Players[i]);
            if (smPlayer is null) continue;
            PlayerSnapshot@ player = PlayerSnapshot();
            player.playerIndex = observation.players.Length;
            player.name = smPlayer.Name;
            observation.players.InsertLast(player);
            PlayerObservation@ state = PlayerObservation();
            @state.player = player;
            auto feedPlayer = race.GetPlayer_V4(player.name);
            if (feedPlayer !is null) {
                state.durationMs = Math::Max(0, feedPlayer.CurrentRaceTime);
                state.checkpointDurationMs = Math::Max(0, feedPlayer.LastCpTime);
                state.checkpointIndex = Math::Max(0, feedPlayer.CpCount);
                state.checkpointLapIndex = race.CPCount == 0 ? state.checkpointIndex : state.checkpointIndex % race.CPCount;
                state.lapNumber = feedPlayer.CurrentLap + 1;
                state.respawnCount = feedPlayer.NbRespawnsRequested;
                state.finished = feedPlayer.IsFinished;
                if (state.finished) state.finishDurationMs = Math::Max(0, feedPlayer.FinishTime);
                state.theoreticalDurationMs = feedPlayer.TheoreticalRaceTime;
                state.lostMs = feedPlayer.TimeLostToRespawns;
            }
            if (i == 0 && state.durationMs + 100 < previousDuration) sessionNumber++;
            observation.playerStates.InsertLast(state);
        }
        if (!observation.playerStates.IsEmpty()) previousDuration = observation.playerStates[0].durationMs;
        observation.active = observation.local && !observation.playerStates.IsEmpty();
        observation.sessionKey = app.RootMap.IdName + ":" + sessionNumber;
        auto vehicle = VehicleState::ViewingPlayerState();
        if (vehicle !is null && !observation.playerStates.IsEmpty()) {
            observation.playerStates[0].throttle = vehicle.InputGasPedal;
        }
        return observation;
    }
}

MapSnapshot@ ReadNextMap(CTrackMania@ app)
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
    auto race = MLFeed::GetRaceData_V4();
    map.totalLaps = race.LapCount;
    map.checkpointsPerLap = race.CPCount;
    return map;
}

ModeSnapshot@ ReadNextMode(CGameManiaPlanetPlayground@ playground)
{
    ModeSnapshot@ mode = ModeSnapshot();
    mode.name = "Local play";
    return mode;
}
#endif
