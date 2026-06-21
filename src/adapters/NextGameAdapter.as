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
        @observation.mode = ReadNextMode(app, splitScreen);
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

ModeSnapshot@ ReadNextMode(CTrackMania@ app, bool splitScreen)
{
    ModeSnapshot@ mode = ModeSnapshot();
    mode.name = splitScreen ? "split-screen" : "solo";
    auto network = cast<CTrackManiaNetwork>(app.Network);
    if (network is null) return mode;
    auto serverInfo = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);
    if (serverInfo is null) return mode;

    mode.modeType = NextModeType(app, serverInfo, splitScreen);
    @mode.settings = NextModeSettings(serverInfo, mode.modeType);
    return mode;
}

string NextModeType(CTrackMania@ app, CTrackManiaNetworkServerInfo@ serverInfo, bool splitScreen)
{
    string scriptMode = NextScriptModeType(NextModeScriptName(app, serverInfo));
    if (scriptMode.Length > 0) return scriptMode;
    return NextLegacyModeType(serverInfo.CurGameMode_Script, splitScreen);
}

string NextModeScriptName(CTrackMania@ app, CTrackManiaNetworkServerInfo@ serverInfo)
{
    string activeScript;
    if (app.PlaygroundScript !is null) activeScript = string(app.PlaygroundScript.ServerModeName);
    return (activeScript + " " + string(serverInfo.CurGameModeStr) + " " + string(serverInfo.CurScriptRelName)).ToLower();
}

string NextScriptModeType(const string &in scriptName)
{
    if (scriptName.Contains("tm_royaltimeattack_")) return "royal-time-attack";
    if (scriptName.Contains("tm_timeattack_")) return "time-attack";
    if (scriptName.Contains("tm_platform_")) return "platform";
    if (scriptName.Contains("tm_rounds_")) return "rounds";
    if (scriptName.Contains("tm_laps_")) return "laps";
    if (scriptName.Contains("tm_cup_")) return "cup";
    return "";
}

string NextLegacyModeType(CTrackManiaNetworkServerInfo::EGameMode_Script gameMode, bool splitScreen)
{
    if (gameMode == CTrackManiaNetworkServerInfo::EGameMode_Script::TimeAttack) return "time-attack";
    if (gameMode == CTrackManiaNetworkServerInfo::EGameMode_Script::Rounds) return "rounds";
    if (gameMode == CTrackManiaNetworkServerInfo::EGameMode_Script::Laps) return "laps";
    if (gameMode == CTrackManiaNetworkServerInfo::EGameMode_Script::Cup) return "cup";
    if (splitScreen) return "unknown";
    if (gameMode == CTrackManiaNetworkServerInfo::EGameMode_Script::Team) return "team";
    if (gameMode == CTrackManiaNetworkServerInfo::EGameMode_Script::Stunts) return "stunts";
    return "script";
}

Json::Value@ NextModeSettings(CTrackManiaNetworkServerInfo@ serverInfo, const string &in modeType)
{
    Json::Value@ settings = Json::Object();
    if (modeType == "time-attack") {
        AddNextTimeAttackSettings(settings, serverInfo);
    } else if (modeType == "rounds") {
        AddNextRoundsSettings(settings, serverInfo);
    } else if (modeType == "team") {
        AddNextTeamSettings(settings, serverInfo);
    } else if (modeType == "laps") {
        AddNextLapsSettings(settings, serverInfo);
    } else if (modeType == "cup") {
        AddNextCupSettings(settings, serverInfo);
    } else if (modeType == "royal-time-attack" || modeType == "platform") {
        settings["timeLimitMs"] = serverInfo.CurTimeAttackLimit;
    }
    return settings;
}

void AddNextTimeAttackSettings(Json::Value@ settings, CTrackManiaNetworkServerInfo@ serverInfo)
{
    settings["timeLimitMs"] = serverInfo.CurTimeAttackLimit;
    settings["synchronizedStartPeriodMs"] = serverInfo.CurTimeAttackSynchStartPeriod;
}

void AddNextRoundsSettings(Json::Value@ settings, CTrackManiaNetworkServerInfo@ serverInfo)
{
    settings["pointsLimit"] = serverInfo.CurRoundUseNewRules
        ? serverInfo.CurRoundPointsLimitNewRules
        : serverInfo.CurRoundPointsLimit;
    settings["forcedLaps"] = serverInfo.CurRoundForcedLaps;
    settings["useNewRules"] = serverInfo.CurRoundUseNewRules;
}

void AddNextTeamSettings(Json::Value@ settings, CTrackManiaNetworkServerInfo@ serverInfo)
{
    settings["pointsLimit"] = serverInfo.CurTeamUseNewRules
        ? serverInfo.CurTeamPointsLimitNewRules
        : serverInfo.CurTeamPointsLimit;
    settings["maxPoints"] = serverInfo.CurTeamMaxPoints;
    settings["useNewRules"] = serverInfo.CurTeamUseNewRules;
}

void AddNextLapsSettings(Json::Value@ settings, CTrackManiaNetworkServerInfo@ serverInfo)
{
    settings["lapCount"] = serverInfo.CurLapsNbLaps;
    settings["timeLimitMs"] = serverInfo.CurLapsTimeLimit;
}

void AddNextCupSettings(Json::Value@ settings, CTrackManiaNetworkServerInfo@ serverInfo)
{
    settings["pointsLimit"] = serverInfo.CurEswcCupPointsLimit;
    settings["roundsPerMap"] = serverInfo.CurEswcCupRoundsPerChallenge;
    settings["winnerCount"] = serverInfo.CurEswcCupNbWinners;
    settings["warmupDurationMs"] = serverInfo.CurEswcCupWarmUpDuration;
}
#endif
