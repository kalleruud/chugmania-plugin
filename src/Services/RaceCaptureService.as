#if TMNEXT
namespace RaceCaptureService
{
    const float AcceleratorThreshold = 0.01f;

    array<PlayerCaptureState@> Players;
    MapCaptureState@ CurrentMap;
    RaceAttemptState@ Attempt = RaceAttemptState();
    bool PlaygroundWasAvailable = false;
    bool AwaitingReset = false;
    uint AttemptOrdinal = 0;

    void Update()
    {
        CTrackMania@ app = cast<CTrackMania>(GetApp());
        if (app is null) return;

        CSmArenaClient@ playground = cast<CSmArenaClient>(app.CurrentPlayground);
        if (playground is null) {
            HandleClosedPlayground();
            return;
        }
        if (playground.Map is null) return;

        PlaygroundWasAvailable = true;
        HandleMapChange(playground);
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData = MLFeed::GetRaceData_V4();
        if (raceData is null || raceData.Map.Length == 0) return;
        if (!PrepareForCapture(raceData)) return;

        SnapshotConfiguration(playground, raceData);
        CapturePlayers(playground, raceData);
        if (Attempt.Active && AllPlayersFinished(playground)) {
            EndAttempt("all_finished", "finished");
        }
    }

    void HandleClosedPlayground()
    {
        if (!PlaygroundWasAvailable) return;
        EndAttempt("playground_closed", "quit");
        ClearState();
        PlaygroundWasAvailable = false;
    }

    void HandleMapChange(CSmArenaClient@ playground)
    {
        if (playground.Map is null) return;
        string nextMapUid = playground.Map.EdChallengeId;
        if (CurrentMap !is null && CurrentMap.Uid == nextMapUid) return;
        EndAttempt("map_changed", "dnf");
        @CurrentMap = SnapshotMap(playground.Map);
        Players.RemoveRange(0, Players.Length);
        ResetAttempt();
        AwaitingReset = false;
        PrintMapInfo(playground);
    }

    MapCaptureState@ SnapshotMap(CGameCtnChallenge@ map)
    {
        MapCaptureState@ snapshot = MapCaptureState();
        snapshot.Uid = map.EdChallengeId;
        snapshot.Name = Text::StripFormatCodes(map.MapName);
        snapshot.AuthorLogin = map.AuthorLogin;
        snapshot.AuthorName = Text::StripFormatCodes(map.AuthorNickName);
        snapshot.MapType = Text::StripFormatCodes(map.MapType);
        snapshot.MapStyle = Text::StripFormatCodes(map.MapStyle);
        snapshot.IsLapRace = map.TMObjective_IsLapRace;
        snapshot.AuthorTimeMs = map.TMObjective_AuthorTime;
        snapshot.GoldTimeMs = map.TMObjective_GoldTime;
        snapshot.SilverTimeMs = map.TMObjective_SilverTime;
        snapshot.BronzeTimeMs = map.TMObjective_BronzeTime;
        return snapshot;
    }

    bool PrepareForCapture(const MLFeed::HookRaceStatsEventsBase_V4@ raceData)
    {
        if (!AwaitingReset) return true;
        if (!ResetIsReady(raceData)) return false;

        Players.RemoveRange(0, Players.Length);
        ResetAttempt();
        AwaitingReset = false;
        print("[" + PluginInfo::Name + "] ATTEMPT_RESET_READY");
        return true;
    }

    void SnapshotConfiguration(
        CSmArenaClient@ playground,
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData
    )
    {
        Attempt.CheckpointsPerLap = int(raceData.CPCount);
        Attempt.WaypointsToFinish = int(raceData.CPsToFinish);
        Attempt.MlFeedLapCount = int(raceData.LapCount_Accurate);
        Attempt.WarmupActive = raceData.WarmupActive;
        SnapshotMode(playground);
    }

    void SnapshotMode(CSmArenaClient@ playground)
    {
        if (playground.Arena is null || playground.Arena.Rules is null ||
            playground.Arena.Rules.RulesMode is null) return;

        CSmArenaRulesMode@ mode = playground.Arena.Rules.RulesMode;
        Attempt.ModeName = string(mode.ServerModeName);
        Attempt.ModeStartTime = int(mode.StartTime);
        Attempt.ModeEndTime = int(mode.EndTime);
        Attempt.ModeTimeLimitMs = mode.EndTime > mode.StartTime
            ? int(mode.EndTime - mode.StartTime) : -1;
        Attempt.LapCountOverride = int(mode.LapCountOverride);
        Attempt.PointsLimit = int(mode.UiScoresPointsLimit);
        Attempt.SpawnDelayDurationMs = int(mode.SpawnDelayDuration);
        Attempt.RespawnBehavior = RespawnBehaviorName(int(mode.RespawnBehaviour));
        Attempt.CheckpointBehavior = CheckpointBehaviorName(int(mode.CheckpointBehaviour));
        Attempt.GiveUpBehavior = GiveUpBehaviorName(int(mode.GiveUpBehaviour));
        Attempt.GiveUpRespawnAfter = mode.GiveUpBehaviour_RespawnAfter;
        Attempt.GiveUpSkipAfterFinish = mode.GiveUpBehaviour_SkipAfterFinishLine;
        Attempt.UsesTeams = mode.UseClans || mode.UseMultiClans || mode.UseForcedClans;
    }

    void CapturePlayers(
        CSmArenaClient@ playground,
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData
    )
    {
        for (uint i = 0; i < playground.Players.Length; i++) {
            if (CapturePlayer(playground, raceData, i)) return;
        }
    }

    bool CapturePlayer(
        CSmArenaClient@ playground,
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
        uint playerIndex
    )
    {
        CSmPlayer@ player = cast<CSmPlayer>(playground.Players[playerIndex]);
        if (player is null || player.ScriptAPI is null) return false;
        CSmScriptPlayer@ scriptPlayer = cast<CSmScriptPlayer>(player.ScriptAPI);
        if (scriptPlayer is null) return false;

        const MLFeed::PlayerCpInfo_V4@ racePlayer = FindRacePlayer(
            raceData, player, scriptPlayer
        );
        if (racePlayer is null || racePlayer.StartTime == 0) return false;

        int terminalIndex = FindTerminalIndex(playground, player);
        PlayerCaptureState@ state = FindPlayerState(playerIndex, terminalIndex);
        if (state is null) {
            @state = StartPlayerIfActive(
                playground, raceData, racePlayer, player, scriptPlayer, playerIndex
            );
            if (state is null) return false;
        } else if (racePlayer.StartTime > state.MlStartTime) {
            EndRestartedAttempt(state);
            return true;
        }

        CaptureEvents(raceData, racePlayer, scriptPlayer, state);
        return false;
    }

    PlayerCaptureState@ StartPlayerIfActive(
        CSmArenaClient@ playground,
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
        const MLFeed::PlayerCpInfo_V4@ racePlayer,
        CSmPlayer@ player,
        CSmScriptPlayer@ scriptPlayer,
        uint playerIndex
    )
    {
        if (!Attempt.Active && !HasRaceActivity(racePlayer, scriptPlayer)) return null;

        PlayerCaptureState@ state = CreatePlayerState(
            playground, playerIndex, player, scriptPlayer, racePlayer
        );
        Players.InsertLast(state);
        EnsureAttemptStarted(raceData);
        AddEvent(state, "start", 0);
        print("[" + PluginInfo::Name + "] PLAYER_STARTED key=" + state.ParticipantKey +
            " gameStartTime=" + state.MlStartTime);
        return state;
    }

    bool HasRaceActivity(
        const MLFeed::PlayerCpInfo_V4@ racePlayer,
        CSmScriptPlayer@ scriptPlayer
    )
    {
        return racePlayer.CpCount > 0 || racePlayer.NbRespawnsRequested > 0 ||
            (racePlayer.CurrentRaceTimeRaw >= 0 &&
                scriptPlayer.InputGasPedal > AcceleratorThreshold);
    }

    void EndRestartedAttempt(PlayerCaptureState@ state)
    {
        state.LastRaceTimeMs = Math::Max(
            state.LastRaceTimeMs,
            int(MLFeed::GameTime) - int(state.MlStartTime)
        );
        if (IsAutomaticRoundTransition()) EndAttempt("round_ended", "dnf");
        else EndAttempt("restart", "restart");
    }

    void EnsureAttemptStarted(const MLFeed::HookRaceStatsEventsBase_V4@ raceData)
    {
        if (CurrentMap is null) return;
        Attempt.CheckpointsPerLap = int(raceData.CPCount);
        Attempt.WaypointsToFinish = int(raceData.CPsToFinish);
        Attempt.MlFeedLapCount = int(raceData.LapCount_Accurate);
        if (Attempt.Active) return;

        Attempt.Active = true;
        Attempt.Ordinal = ++AttemptOrdinal;
        Attempt.StartedAtUtcMs = EarliestPlayerStart();
        Attempt.AttemptId = CurrentMap.Uid + "-" + Time::Stamp + "-" + Attempt.Ordinal;
        print("[" + PluginInfo::Name + "] ATTEMPT_STARTED id=" + Attempt.AttemptId +
            " timing=mlfeed_game_clock");
    }

    void CaptureEvents(
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
        const MLFeed::PlayerCpInfo_V4@ racePlayer,
        CSmScriptPlayer@ scriptPlayer,
        PlayerCaptureState@ state
    )
    {
        SnapshotPlayerTelemetry(racePlayer, state);
        CaptureRespawns(racePlayer, state);
        CaptureCheckpoints(raceData, racePlayer, state);
        CaptureFirstThrottle(racePlayer, scriptPlayer, state);
    }

    void SnapshotPlayerTelemetry(
        const MLFeed::PlayerCpInfo_V4@ racePlayer,
        PlayerCaptureState@ state
    )
    {
        state.LastRaceTimeMs = Math::Max(state.LastRaceTimeMs, racePlayer.CurrentRaceTimeRaw);
        state.AccountId = racePlayer.WebServicesUserId;
        if (racePlayer.Login.Length > 0) state.Login = racePlayer.Login;
        state.IsLocalPlayer = racePlayer.IsLocalPlayer;
        state.TheoreticalRaceTimeMs = racePlayer.IsFinished
            ? racePlayer.LastTheoreticalCpTime
            : Math::Max(racePlayer.TheoreticalRaceTime, 0);
        state.RaceRank = PositiveOrMissing(racePlayer.RaceRank);
        state.RaceRespawnRank = PositiveOrMissing(racePlayer.RaceRespawnRank);
        state.TimeAttackRank = PositiveOrMissing(racePlayer.TaRank);
        state.LatencyEstimateMs = racePlayer.latencyEstimate;
        state.LatencySampleCount = racePlayer.lagDataPoints;
        CopyTimes(racePlayer.BestRaceTimes, state.BestRaceTimes);
        CopyTimes(racePlayer.BestLapTimes, state.BestLapTimes);
    }

    int PositiveOrMissing(uint value)
    {
        return value > 0 ? int(value) : -1;
    }

    void CopyTimes(const array<uint>@ source, array<uint>@ destination)
    {
        destination.RemoveRange(0, destination.Length);
        if (source is null) return;
        for (uint i = 0; i < source.Length; i++) destination.InsertLast(source[i]);
    }

    void CaptureRespawns(
        const MLFeed::PlayerCpInfo_V4@ racePlayer,
        PlayerCaptureState@ state
    )
    {
        uint requested = racePlayer.NbRespawnsRequested;
        const array<int>@ respawnTimes = racePlayer.RespawnTimes;
        uint available = respawnTimes is null ? 0 : respawnTimes.Length;
        uint captured = uint(Math::Max(state.CapturedRespawnEvents, 0));
        uint toCapture = requested < available ? requested : available;

        while (captured < toCapture) {
            bool isNewest = captured + 1 == requested;
            int checkpointIndex = isNewest ? int(racePlayer.LastRespawnCheckpoint) : -1;
            AddRespawnEvent(state, int(captured + 1), respawnTimes[captured], checkpointIndex);
            captured++;
        }
        state.CapturedRespawnEvents = int(captured);
    }

    void CaptureCheckpoints(
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
        const MLFeed::PlayerCpInfo_V4@ racePlayer,
        PlayerCaptureState@ state
    )
    {
        while (state.LastCapturedCp < racePlayer.CpCount) {
            int checkpointIndex = state.LastCapturedCp + 1;
            if (uint(checkpointIndex) >= racePlayer.CpTimes.Length) break;
            int durationMs = racePlayer.CpTimes[checkpointIndex];
            if (durationMs <= 0) break;

            bool isFinish = uint(checkpointIndex) == raceData.CPsToFinish;
            AddCheckpointEvent(state, racePlayer, checkpointIndex, durationMs, isFinish);
            state.LastCapturedCp = checkpointIndex;
            if (isFinish) state.Finished = true;
        }

        if (!state.Finished && racePlayer.IsFinished && racePlayer.LastCpTime > 0) {
            AddCheckpointEvent(
                state, racePlayer, racePlayer.CpCount, racePlayer.LastCpTime, true
            );
            state.LastCapturedCp = racePlayer.CpCount;
            state.Finished = true;
        }
    }

    void CaptureFirstThrottle(
        const MLFeed::PlayerCpInfo_V4@ racePlayer,
        CSmScriptPlayer@ scriptPlayer,
        PlayerCaptureState@ state
    )
    {
        if (state.AcceleratorRecorded || racePlayer.CurrentRaceTimeRaw < 0 ||
            scriptPlayer.InputGasPedal <= AcceleratorThreshold) return;

        state.AcceleratorRecorded = true;
        AddEvent(state, "first_throttle", racePlayer.CurrentRaceTimeRaw);
        print("[" + PluginInfo::Name + "] FIRST_THROTTLE key=" + state.ParticipantKey +
            " durationMs=" + racePlayer.CurrentRaceTimeRaw);
    }

    void AddEvent(PlayerCaptureState@ state, const string &in type, int durationMs)
    {
        RaceEventCapture@ event = NewEvent(state, type, durationMs);
        state.Events.InsertLast(event);
    }

    RaceEventCapture@ NewEvent(
        PlayerCaptureState@ state,
        const string &in type,
        int durationMs
    )
    {
        RaceEventCapture@ event = RaceEventCapture();
        event.CaptureOrder = state.Events.Length;
        event.Type = type;
        event.DurationMs = Math::Max(durationMs, 0);
        event.AtUtc = EventUtc(state, event.DurationMs);
        return event;
    }

    void AddCheckpointEvent(
        PlayerCaptureState@ state,
        const MLFeed::PlayerCpInfo_V4@ racePlayer,
        int checkpointIndex,
        int durationMs,
        bool isFinish
    )
    {
        RaceEventCapture@ event = NewEvent(
            state, isFinish ? "finish" : "checkpoint", durationMs
        );
        event.CheckpointIndex = checkpointIndex;
        if (racePlayer.TimeLostToRespawnByCp !is null) {
            event.TheoreticalDurationMs = durationMs - CumulativeRespawnLoss(
                racePlayer.TimeLostToRespawnByCp, checkpointIndex
            );
        }
        state.Events.InsertLast(event);

        print("[" + PluginInfo::Name + "] " + event.Type.ToUpper() +
            " key=" + state.ParticipantKey + " checkpoint=" + checkpointIndex +
            " durationMs=" + durationMs);
    }

    int CumulativeRespawnLoss(const array<int>@ losses, int checkpointIndex)
    {
        int total = 0;
        uint requestedCount = uint(Math::Max(checkpointIndex, 0));
        uint count = requestedCount < losses.Length ? requestedCount : losses.Length;
        for (uint i = 0; i < count; i++) total += losses[i];
        return total;
    }

    void AddRespawnEvent(
        PlayerCaptureState@ state,
        int ordinal,
        int durationMs,
        int checkpointIndex
    )
    {
        RaceEventCapture@ event = NewEvent(state, "respawn", durationMs);
        event.CheckpointIndex = checkpointIndex;
        state.Events.InsertLast(event);
        print("[" + PluginInfo::Name + "] RESPAWN key=" + state.ParticipantKey +
            " ordinal=" + ordinal + " durationMs=" + durationMs);
    }

    PlayerCaptureState@ FindPlayerState(uint playerIndex, int terminalIndex)
    {
        for (uint i = 0; i < Players.Length; i++) {
            if (Players[i].PlayerIndex == playerIndex &&
                Players[i].TerminalIndex == terminalIndex) return Players[i];
        }
        return null;
    }

    PlayerCaptureState@ CreatePlayerState(
        CSmArenaClient@ playground,
        uint playerIndex,
        CSmPlayer@ player,
        CSmScriptPlayer@ scriptPlayer,
        const MLFeed::PlayerCpInfo_V4@ racePlayer
    )
    {
        PlayerCaptureState@ state = PlayerCaptureState();
        state.PlayerIndex = playerIndex;
        state.TerminalIndex = FindTerminalIndex(playground, player);
        state.Login = racePlayer.Login.Length > 0 ? racePlayer.Login : scriptPlayer.Login;
        state.AccountId = racePlayer.WebServicesUserId;
        state.Name = Text::StripFormatCodes(racePlayer.Name);
        FillFallbackIdentity(state, player, playerIndex);
        state.IsFake = scriptPlayer.IsFakePlayer;
        state.IsBot = scriptPlayer.IsBot;
        state.SpawnIndex = int(racePlayer.SpawnIndex);
        state.MlStartTime = racePlayer.StartTime;
        state.LastRaceTimeMs = Math::Max(racePlayer.CurrentRaceTimeRaw, 0);
        state.StartedAtUtcMs = UtcClockService::CurrentMs() - state.LastRaceTimeMs;
        if (Attempt.Active && state.StartedAtUtcMs < Attempt.StartedAtUtcMs) {
            Attempt.StartedAtUtcMs = state.StartedAtUtcMs;
        }
        return state;
    }

    void FillFallbackIdentity(
        PlayerCaptureState@ state,
        CSmPlayer@ player,
        uint playerIndex
    )
    {
        if (state.Login.Length == 0 && player.User !is null) state.Login = player.User.Login;
        if (state.Name.Length == 0 && player.User !is null) {
            state.Name = Text::StripFormatCodes(player.User.Name);
        }
        state.ParticipantKey = state.AccountId.Length > 0 ? state.AccountId :
            (state.Login.Length > 0 ? state.Login :
                "local-player-" + playerIndex + "-terminal-" + state.TerminalIndex);
    }

    const MLFeed::PlayerCpInfo_V4@ FindRacePlayer(
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
        CSmPlayer@ player,
        CSmScriptPlayer@ scriptPlayer
    )
    {
        string login = scriptPlayer.Login;
        if (login.Length == 0 && player.User !is null) login = player.User.Login;

        const MLFeed::PlayerCpInfo_V4@ racePlayer;
        if (login.Length > 0) @racePlayer = raceData.GetPlayer_V4_ByLogin(login);
        if (racePlayer !is null) return racePlayer;

        string name = Text::StripFormatCodes(scriptPlayer.Name);
        if (name.Length == 0 && player.User !is null) {
            name = Text::StripFormatCodes(player.User.Name);
        }
        if (name.Length == 0) return null;
        return raceData.GetPlayer_V4(name);
    }

    bool ResetIsReady(const MLFeed::HookRaceStatsEventsBase_V4@ raceData)
    {
        if (Players.Length == 0) return true;
        for (uint i = 0; i < Players.Length; i++) {
            const MLFeed::PlayerCpInfo_V4@ racePlayer = FindPreviousRacePlayer(
                raceData, Players[i]
            );
            if (racePlayer is null || racePlayer.StartTime <= Players[i].MlStartTime) return false;
            if (racePlayer.CpCount != 0 || racePlayer.NbRespawnsRequested != 0) return false;
        }
        return true;
    }

    const MLFeed::PlayerCpInfo_V4@ FindPreviousRacePlayer(
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
        PlayerCaptureState@ state
    )
    {
        const MLFeed::PlayerCpInfo_V4@ racePlayer;
        if (state.Login.Length > 0) @racePlayer = raceData.GetPlayer_V4_ByLogin(state.Login);
        if (racePlayer is null && state.Name.Length > 0) {
            @racePlayer = raceData.GetPlayer_V4(state.Name);
        }
        return racePlayer;
    }

    bool AllPlayersFinished(CSmArenaClient@ playground)
    {
        if (Players.Length == 0 || Players.Length < playground.Players.Length) return false;
        for (uint i = 0; i < Players.Length; i++) {
            if (!Players[i].Finished) return false;
        }
        return true;
    }

    void EndAttempt(const string &in endReason, const string &in unfinishedOutcome)
    {
        if (!Attempt.Active || CurrentMap is null || Players.Length == 0) return;
        AddMissingTerminalEvents(unfinishedOutcome);
        ComputeFinishPositions();

        Attempt.StartedAtUtcMs = EarliestPlayerStart();
        int64 endedAtUtcMs = LatestPlayerEnd();
        CompletedRaceAttempt@ completed = BuildCompletedAttempt(
            endReason, endedAtUtcMs
        );
        string body = Json::Write(PayloadService::Build(completed));
        print("[" + PluginInfo::Name + "] ATTEMPT_ENDED id=" + Attempt.AttemptId +
            " reason=" + endReason + " durationMs=" + completed.DurationMs);
        QueueWebhook(body);

        Attempt.Active = false;
        AwaitingReset = true;
    }

    void AddMissingTerminalEvents(const string &in outcome)
    {
        for (uint i = 0; i < Players.Length; i++) {
            if (!Players[i].Finished) AddEvent(Players[i], outcome, Players[i].LastRaceTimeMs);
        }
    }

    CompletedRaceAttempt@ BuildCompletedAttempt(
        const string &in endReason,
        int64 endedAtUtcMs
    )
    {
        CompletedRaceAttempt@ completed = CompletedRaceAttempt();
        @completed.Attempt = Attempt;
        @completed.Map = CurrentMap;
        for (uint i = 0; i < Players.Length; i++) completed.Players.InsertLast(Players[i]);
        completed.EndReason = endReason;
        completed.EndedAtUtc = UtcClockService::Format(endedAtUtcMs);
        completed.DurationMs = int(endedAtUtcMs - Attempt.StartedAtUtcMs);
        return completed;
    }

    void QueueWebhook(const string &in body)
    {
        if (Setting_WebhookEnabled && Setting_WebhookEndpoint.Length > 0) {
            WebhookService::Enqueue(Attempt.AttemptId, body);
            WebhookService::StartDelivery();
        } else {
            print("[" + PluginInfo::Name + "] WEBHOOK_SKIPPED disabled or endpoint missing");
        }
    }

    void ComputeFinishPositions()
    {
        for (uint i = 0; i < Players.Length; i++) {
            PlayerCaptureState@ player = Players[i];
            if (!player.Finished) continue;
            player.FinishPosition = FinishPosition(player);
        }
    }

    int FinishPosition(PlayerCaptureState@ player)
    {
        int finishTime = LastEventDuration(player);
        int position = 1;
        for (uint i = 0; i < Players.Length; i++) {
            PlayerCaptureState@ other = Players[i];
            if (!other.Finished || other is player) continue;
            int otherTime = LastEventDuration(other);
            if (otherTime < finishTime ||
                (otherTime == finishTime && other.PlayerIndex < player.PlayerIndex)) position++;
        }
        return position;
    }

    int64 EarliestPlayerStart()
    {
        if (Players.Length == 0) return 0;
        int64 earliest = Players[0].StartedAtUtcMs;
        for (uint i = 1; i < Players.Length; i++) {
            if (Players[i].StartedAtUtcMs < earliest) earliest = Players[i].StartedAtUtcMs;
        }
        return earliest;
    }

    int64 LatestPlayerEnd()
    {
        int64 latest = EarliestPlayerStart();
        for (uint i = 0; i < Players.Length; i++) {
            int64 playerEnd = Players[i].StartedAtUtcMs + LastEventDuration(Players[i]);
            if (playerEnd > latest) latest = playerEnd;
        }
        return latest;
    }

    int LastEventDuration(PlayerCaptureState@ state)
    {
        int durationMs = state.Events.Length == 0 ? state.LastRaceTimeMs : 0;
        for (uint i = 0; i < state.Events.Length; i++) {
            durationMs = Math::Max(durationMs, state.Events[i].DurationMs);
        }
        return durationMs;
    }

    string EventUtc(PlayerCaptureState@ state, int durationMs)
    {
        return UtcClockService::Format(state.StartedAtUtcMs + durationMs);
    }

    bool IsAutomaticRoundTransition()
    {
        string mode = Attempt.ModeName.ToLower();
        return mode.Contains("round") || mode.Contains("cup") ||
            mode.Contains("royal") || mode.Contains("platform");
    }

    string RespawnBehaviorName(int value)
    {
        if (value == 1) return "do_nothing";
        if (value == 2) return "give_up_before_first_checkpoint";
        if (value == 3) return "always_give_up";
        if (value == 4) return "always_respawn";
        return "custom";
    }

    string CheckpointBehaviorName(int value)
    {
        if (value == 1) return "default";
        if (value == 2) return "infinite_laps";
        return "custom";
    }

    string GiveUpBehaviorName(int value)
    {
        if (value == 1) return "do_nothing";
        if (value == 2) return "give_up";
        return "custom";
    }

    int FindTerminalIndex(CSmArenaClient@ playground, CSmPlayer@ player)
    {
        for (uint i = 0; i < playground.GameTerminals.Length; i++) {
            if (playground.GameTerminals[i].ControlledPlayer is player) return int(i);
        }
        return -1;
    }

    void PrintMapInfo(CSmArenaClient@ playground)
    {
        if (playground.Map is null) return;
        print("[" + PluginInfo::Name + "] MAP uid=" + playground.Map.EdChallengeId +
            " name=\"" + Text::StripFormatCodes(playground.Map.MapName) + "\"" +
            " players=" + playground.Players.Length +
            " terminals=" + playground.GameTerminals.Length);
    }

    void ResetAttempt()
    {
        @Attempt = RaceAttemptState();
    }

    void ClearState()
    {
        Players.RemoveRange(0, Players.Length);
        @CurrentMap = null;
        ResetAttempt();
        AwaitingReset = false;
    }
}
#elif TURBO
namespace RaceCaptureService
{
    const float AcceleratorThreshold = 0.01f;

    array<PlayerCaptureState@> Players;
    MapCaptureState@ CurrentMap;
    RaceAttemptState@ Attempt = RaceAttemptState();
    bool PlaygroundWasAvailable = false;
    uint AttemptOrdinal = 0;

    void Update()
    {
        CTrackMania@ app = cast<CTrackMania>(GetApp());
        if (app is null) return;

        CTrackManiaRace@ playground = cast<CTrackManiaRace>(app.CurrentPlayground);
        if (playground is null) {
            HandleClosedPlayground();
            return;
        }
        if (app.Challenge is null) return;

        PlaygroundWasAvailable = true;
        HandleMapChange(app.Challenge, playground);
        CapturePlayers(playground);
        if (Attempt.Active && AllPlayersFinished()) {
            EndAttempt("all_finished", "finished");
        }
    }

    void HandleClosedPlayground()
    {
        if (!PlaygroundWasAvailable) return;
        EndAttempt("playground_closed", "quit");
        ClearState();
        PlaygroundWasAvailable = false;
    }

    void HandleMapChange(CGameCtnChallenge@ map, CTrackManiaRace@ playground)
    {
        string nextMapUid = map.EdChallengeId;
        if (CurrentMap !is null && CurrentMap.Uid == nextMapUid) return;
        EndAttempt("map_changed", "dnf");
        @CurrentMap = SnapshotMap(map);
        ClearAttempt();
        print("[" + PluginInfo::Name + "] MAP uid=" + CurrentMap.Uid +
            " name=\"" + CurrentMap.Name + "\" players=" + playground.Players.Length +
            " terminals=" + playground.GameTerminals.Length);
    }

    MapCaptureState@ SnapshotMap(CGameCtnChallenge@ map)
    {
        MapCaptureState@ snapshot = MapCaptureState();
        snapshot.Uid = map.EdChallengeId;
        snapshot.Name = Text::StripFormatCodes(map.MapName);
        snapshot.AuthorLogin = map.AuthorLogin;
        snapshot.AuthorName = Text::StripFormatCodes(map.AuthorNickName);
        snapshot.MapType = Text::StripFormatCodes(map.MapType);
        snapshot.MapStyle = Text::StripFormatCodes(map.MapStyle);
        snapshot.IsLapRace = map.TMObjective_IsLapRace;
        snapshot.Laps = int(map.TMObjective_NbLaps);
        snapshot.AuthorTimeMs = int(map.TMObjective_AuthorTime);
        snapshot.GoldTimeMs = int(map.TMObjective_GoldTime);
        snapshot.SilverTimeMs = int(map.TMObjective_SilverTime);
        snapshot.BronzeTimeMs = int(map.TMObjective_BronzeTime);
        return snapshot;
    }

    void CapturePlayers(CTrackManiaRace@ playground)
    {
        for (uint i = 0; i < playground.Players.Length; i++) {
            CTrackManiaPlayer@ player = cast<CTrackManiaPlayer>(playground.Players[i]);
            if (player is null || !IsRacing(player)) continue;

            int terminalIndex = FindTerminalIndex(playground, player);
            PlayerCaptureState@ state = FindPlayerState(i, terminalIndex);
            if (state is null) {
                @state = StartPlayer(playground, player, i, terminalIndex);
            } else if (player.RaceStartTime > state.NativeStartTime) {
                EndAttempt("restart", "restart");
                ClearAttempt();
                return;
            }
            CaptureEvents(player, state);
        }
    }

    bool IsRacing(CTrackManiaPlayer@ player)
    {
        return player.RaceStartTime > 0 &&
            (player.RaceState == CTrackManiaPlayer::ERaceState::Running ||
             player.RaceState == CTrackManiaPlayer::ERaceState::Finished);
    }

    PlayerCaptureState@ StartPlayer(
        CTrackManiaRace@ playground,
        CTrackManiaPlayer@ player,
        uint playerIndex,
        int terminalIndex
    )
    {
        PlayerCaptureState@ state = PlayerCaptureState();
        state.PlayerIndex = playerIndex;
        state.TerminalIndex = terminalIndex;
        state.Login = player.Login;
        state.Name = Text::StripFormatCodes(player.Name);
        state.ParticipantKey = state.Login.Length > 0 ? state.Login :
            "local-player-" + playerIndex + "-terminal-" + terminalIndex;
        state.NativeStartTime = player.RaceStartTime;

        int knownDuration = LatestKnownDuration(player);
        state.LastRaceTimeMs = knownDuration;
        state.StartedAtMonotonicMs = Time::Now - uint64(knownDuration);
        state.StartedAtUtcMs = UtcClockService::CurrentMs() - knownDuration;
        Players.InsertLast(state);
        EnsureAttemptStarted();
        if (Players.Length > 1) Attempt.ModeName = "local_split_screen";
        AddEvent(state, "start", 0);
        print("[" + PluginInfo::Name + "] PLAYER_STARTED key=" + state.ParticipantKey +
            " gameStartTime=" + state.NativeStartTime);
        return state;
    }

    int LatestKnownDuration(CTrackManiaPlayer@ player)
    {
        int duration = 0;
        if (player.CurRace !is null) {
            for (uint i = 0; i < player.CurRace.Checkpoints.Length; i++) {
                duration = Math::Max(duration, player.CurRace.Checkpoints[i]);
            }
            if (player.CurRace.Time > 0) duration = Math::Max(duration, player.CurRace.Time);
        }
        return duration;
    }

    void EnsureAttemptStarted()
    {
        if (Attempt.Active || CurrentMap is null) return;
        Attempt.Active = true;
        Attempt.Ordinal = ++AttemptOrdinal;
        Attempt.StartedAtUtcMs = EarliestPlayerStart();
        Attempt.AttemptId = CurrentMap.Uid + "-" + Time::Stamp + "-" + Attempt.Ordinal;
        Attempt.ModeName = Players.Length > 1 ? "local_split_screen" : "local_solo";
        print("[" + PluginInfo::Name + "] ATTEMPT_STARTED id=" + Attempt.AttemptId +
            " timing=turbo_native_race_clock");
    }

    void CaptureEvents(CTrackManiaPlayer@ player, PlayerCaptureState@ state)
    {
        int elapsed = CurrentDuration(state);
        state.LastRaceTimeMs = Math::Max(state.LastRaceTimeMs, elapsed);
        CaptureRespawns(player, state, elapsed);
        CaptureCheckpoints(player, state);
        CaptureFirstThrottle(player, state, elapsed);
        CaptureFinish(player, state);
    }

    int CurrentDuration(PlayerCaptureState@ state)
    {
        return int(Time::Now - state.StartedAtMonotonicMs);
    }

    void CaptureRespawns(
        CTrackManiaPlayer@ player,
        PlayerCaptureState@ state,
        int elapsed
    )
    {
        while (state.CapturedRespawnEvents < int(player.NbRespawns)) {
            state.CapturedRespawnEvents++;
            RaceEventCapture@ event = NewEvent(state, "respawn", elapsed);
            state.Events.InsertLast(event);
            print("[" + PluginInfo::Name + "] RESPAWN key=" + state.ParticipantKey +
                " ordinal=" + state.CapturedRespawnEvents + " durationMs=" + elapsed);
        }
    }

    void CaptureCheckpoints(CTrackManiaPlayer@ player, PlayerCaptureState@ state)
    {
        if (player.CurRace is null) return;
        while (state.LastCapturedCp < int(player.CurRace.Checkpoints.Length)) {
            int checkpointIndex = state.LastCapturedCp + 1;
            int duration = player.CurRace.Checkpoints[checkpointIndex - 1];
            if (duration <= 0) break;
            RaceEventCapture@ event = NewEvent(state, "checkpoint", duration);
            event.CheckpointIndex = checkpointIndex;
            state.Events.InsertLast(event);
            state.LastCapturedCp = checkpointIndex;
            state.LastRaceTimeMs = Math::Max(state.LastRaceTimeMs, duration);
            print("[" + PluginInfo::Name + "] CHECKPOINT key=" + state.ParticipantKey +
                " checkpoint=" + checkpointIndex + " durationMs=" + duration);
        }
    }

    void CaptureFirstThrottle(
        CTrackManiaPlayer@ player,
        PlayerCaptureState@ state,
        int elapsed
    )
    {
        if (state.AcceleratorRecorded || player.InputGasPedal <= AcceleratorThreshold) return;
        state.AcceleratorRecorded = true;
        AddEvent(state, "first_throttle", elapsed);
        print("[" + PluginInfo::Name + "] FIRST_THROTTLE key=" + state.ParticipantKey +
            " durationMs=" + elapsed);
    }

    void CaptureFinish(CTrackManiaPlayer@ player, PlayerCaptureState@ state)
    {
        if (state.Finished || player.RaceState != CTrackManiaPlayer::ERaceState::Finished) return;
        int duration = player.CurRace !is null && player.CurRace.Time > 0
            ? player.CurRace.Time : CurrentDuration(state);
        RaceEventCapture@ event = NewEvent(state, "finish", duration);
        event.CheckpointIndex = state.LastCapturedCp + 1;
        state.Events.InsertLast(event);
        state.LastRaceTimeMs = Math::Max(state.LastRaceTimeMs, duration);
        state.Finished = true;
        print("[" + PluginInfo::Name + "] FINISH key=" + state.ParticipantKey +
            " checkpoint=" + event.CheckpointIndex + " durationMs=" + duration);
    }

    PlayerCaptureState@ FindPlayerState(uint playerIndex, int terminalIndex)
    {
        for (uint i = 0; i < Players.Length; i++) {
            if (Players[i].PlayerIndex == playerIndex &&
                Players[i].TerminalIndex == terminalIndex) return Players[i];
        }
        return null;
    }

    int FindTerminalIndex(CTrackManiaRace@ playground, CTrackManiaPlayer@ player)
    {
        for (uint i = 0; i < playground.GameTerminals.Length; i++) {
            if (playground.GameTerminals[i].ControlledPlayer is player) return int(i);
        }
        return -1;
    }

    bool AllPlayersFinished()
    {
        if (Players.Length == 0) return false;
        for (uint i = 0; i < Players.Length; i++) {
            if (!Players[i].Finished) return false;
        }
        return true;
    }

    void EndAttempt(const string &in endReason, const string &in unfinishedOutcome)
    {
        if (!Attempt.Active || CurrentMap is null || Players.Length == 0) return;
        AddMissingTerminalEvents(unfinishedOutcome);
        ComputeFinishPositions();
        Attempt.StartedAtUtcMs = EarliestPlayerStart();
        int64 endedAtUtcMs = LatestPlayerEnd();
        CompletedRaceAttempt@ completed = BuildCompletedAttempt(endReason, endedAtUtcMs);
        string body = Json::Write(PayloadService::Build(completed));
        print("[" + PluginInfo::Name + "] ATTEMPT_ENDED id=" + Attempt.AttemptId +
            " reason=" + endReason + " durationMs=" + completed.DurationMs);
        QueueWebhook(body);
        Attempt.Active = false;
    }

    void AddMissingTerminalEvents(const string &in outcome)
    {
        for (uint i = 0; i < Players.Length; i++) {
            if (!Players[i].Finished) AddEvent(Players[i], outcome, Players[i].LastRaceTimeMs);
        }
    }

    CompletedRaceAttempt@ BuildCompletedAttempt(const string &in reason, int64 endedAtUtcMs)
    {
        CompletedRaceAttempt@ completed = CompletedRaceAttempt();
        @completed.Attempt = Attempt;
        @completed.Map = CurrentMap;
        for (uint i = 0; i < Players.Length; i++) completed.Players.InsertLast(Players[i]);
        completed.EndReason = reason;
        completed.EndedAtUtc = UtcClockService::Format(endedAtUtcMs);
        completed.DurationMs = int(endedAtUtcMs - Attempt.StartedAtUtcMs);
        return completed;
    }

    void QueueWebhook(const string &in body)
    {
        if (Setting_WebhookEnabled && Setting_WebhookEndpoint.Length > 0) {
            WebhookService::Enqueue(Attempt.AttemptId, body);
            WebhookService::StartDelivery();
        } else {
            print("[" + PluginInfo::Name + "] WEBHOOK_SKIPPED disabled or endpoint missing");
        }
    }

    void AddEvent(PlayerCaptureState@ state, const string &in type, int durationMs)
    {
        state.Events.InsertLast(NewEvent(state, type, durationMs));
    }

    RaceEventCapture@ NewEvent(PlayerCaptureState@ state, const string &in type, int durationMs)
    {
        RaceEventCapture@ event = RaceEventCapture();
        event.CaptureOrder = state.Events.Length;
        event.Type = type;
        event.DurationMs = Math::Max(durationMs, 0);
        event.AtUtc = EventUtc(state, event.DurationMs);
        return event;
    }

    void ComputeFinishPositions()
    {
        for (uint i = 0; i < Players.Length; i++) {
            if (!Players[i].Finished) continue;
            int position = 1;
            int finishTime = LastEventDuration(Players[i]);
            for (uint j = 0; j < Players.Length; j++) {
                if (!Players[j].Finished || i == j) continue;
                int otherTime = LastEventDuration(Players[j]);
                if (otherTime < finishTime ||
                    (otherTime == finishTime && Players[j].PlayerIndex < Players[i].PlayerIndex)) {
                    position++;
                }
            }
            Players[i].FinishPosition = position;
        }
    }

    int64 EarliestPlayerStart()
    {
        if (Players.Length == 0) return 0;
        int64 earliest = Players[0].StartedAtUtcMs;
        for (uint i = 1; i < Players.Length; i++) {
            if (Players[i].StartedAtUtcMs < earliest) earliest = Players[i].StartedAtUtcMs;
        }
        return earliest;
    }

    int64 LatestPlayerEnd()
    {
        int64 latest = EarliestPlayerStart();
        for (uint i = 0; i < Players.Length; i++) {
            int64 playerEnd = Players[i].StartedAtUtcMs + LastEventDuration(Players[i]);
            if (playerEnd > latest) latest = playerEnd;
        }
        return latest;
    }

    int LastEventDuration(PlayerCaptureState@ state)
    {
        int duration = state.LastRaceTimeMs;
        for (uint i = 0; i < state.Events.Length; i++) {
            duration = Math::Max(duration, state.Events[i].DurationMs);
        }
        return duration;
    }

    string EventUtc(PlayerCaptureState@ state, int durationMs)
    {
        return UtcClockService::Format(state.StartedAtUtcMs + durationMs);
    }

    void ClearAttempt()
    {
        Players.RemoveRange(0, Players.Length);
        @Attempt = RaceAttemptState();
    }

    void ClearState()
    {
        ClearAttempt();
        @CurrentMap = null;
    }
}
#endif
