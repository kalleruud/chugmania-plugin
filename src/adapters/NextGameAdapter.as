#if TMNEXT
class NextGameAdapter : GameAdapter
{
    string lastMap;
    bool roundActive;
    uint activeSpawnIndex;

    GameObservation@ Observe()
    {
        GameObservation@ observation = GameObservation();
        CTrackMania@ app = cast<CTrackMania>(GetApp());
        if (app is null || app.CurrentPlayground is null || app.RootMap is null) return observation;
        auto playground = app.CurrentPlayground;
        observation.local = app.Network !is null && app.Network.PlaygroundClientScriptAPI !is null &&
            app.Network.PlaygroundClientScriptAPI.IsServerOrSolo;
        @observation.map = ReadNextMap(app);
        if (lastMap != app.RootMap.IdName) {
            lastMap = app.RootMap.IdName;
            roundActive = false;
        }
        bool playerDriving;
        for (uint i = 0; i < playground.GameTerminals.Length; i++) {
            auto terminal = playground.GameTerminals[i];
            if (terminal.UISequence_Current != SGamePlaygroundUIConfig::EUISequence::Playing) continue;
            if (terminal.GUIPlayer is null || terminal.ControlledPlayer is null) continue;
            if (terminal.GUIPlayer.User.Id.Value != terminal.ControlledPlayer.User.Id.Value) continue;
            playerDriving = true;
            break;
        }
        auto race = MLFeed::GetRaceData_V4();
        for (uint i = 0; i < playground.Players.Length; i++) {
            auto smPlayer = cast<CSmPlayer>(playground.Players[i]);
            if (smPlayer is null) continue;
            auto feedPlayer = race.GetPlayer_V4(smPlayer.User.Name);
            if (feedPlayer is null) continue;
            int raceTime = feedPlayer.CurrentRaceTime;
            if (!roundActive && playerDriving && feedPlayer.PlayerIsRacing && raceTime >= 0) {
                activeSpawnIndex = feedPlayer.SpawnIndex;
                roundActive = true;
            }
            if (!roundActive || !feedPlayer.PlayerIsRacing || feedPlayer.SpawnIndex != activeSpawnIndex) continue;
            PlayerSnapshot@ player = PlayerSnapshot();
            player.playerIndex = observation.players.Length;
            player.name = smPlayer.User.Name;
            player.login = feedPlayer.Login;
            if (feedPlayer.Login.Length > 0) player.localId = "" + feedPlayer.LoginMwId.Value;
            player.accountId = feedPlayer.WebServicesUserId;
            observation.players.InsertLast(player);
            PlayerObservation@ state = PlayerObservation();
            @state.player = player;
            state.durationMs = uint(raceTime);
            state.checkpointDurationMs = Math::Max(0, feedPlayer.LastCpTime);
            state.checkpointIndex = Math::Max(0, feedPlayer.CpCount);
            state.checkpointLapIndex = race.CPCount == 0 ? state.checkpointIndex : state.checkpointIndex % race.CPCount;
            state.lapNumber = feedPlayer.CurrentLap + 1;
            state.respawnCount = feedPlayer.NbRespawnsRequested;
            state.finished = feedPlayer.IsFinished;
            if (state.finished) state.finishDurationMs = Math::Max(0, feedPlayer.FinishTime);
            state.theoreticalDurationMs = feedPlayer.LastTheoreticalCpTime;
            state.lostMs = feedPlayer.TimeLostToRespawns;
            observation.playerStates.InsertLast(state);
        }
        bool splitScreen = playground.GameTerminals.Length > 1 || observation.players.Length > 1;
        @observation.mode = ReadNextMode(splitScreen);
        observation.active = observation.local && !observation.playerStates.IsEmpty();
        if (observation.active) {
            observation.sessionKey = app.RootMap.IdName + ":" + activeSpawnIndex;
        } else {
            if (roundActive) roundActive = false;
            observation.endReason = "unknown";
        }
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
    map.isLaps = app.RootMap.TMObjective_IsLapRace;
    map.authorTime = app.RootMap.TMObjective_AuthorTime;
    map.goldTime = app.RootMap.TMObjective_GoldTime;
    map.silverTime = app.RootMap.TMObjective_SilverTime;
    map.bronzeTime = app.RootMap.TMObjective_BronzeTime;
    auto race = MLFeed::GetRaceData_V4();
    map.totalLaps = race.LapCount;
    map.checkpointsPerLap = race.CPCount;
    return map;
}

ModeSnapshot@ ReadNextMode(bool splitScreen)
{
    ModeSnapshot@ mode = ModeSnapshot();
    mode.name = splitScreen ? "split-screen" : "solo";
    return mode;
}
#endif
