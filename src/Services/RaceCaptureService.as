namespace RaceCaptureService
{
    const float AcceleratorThreshold = 0.01f;
    const string UnknownVehicleType = "unknown";

    array<PlayerCaptureState@> Players;
    CGameCtnChallenge@ CurrentMap;
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
        if (CurrentMap is playground.Map) return;
        EndAttempt("map_changed", "dnf");
        @CurrentMap = playground.Map;
        Players.RemoveRange(0, Players.Length);
        ResetAttempt();
        AwaitingReset = false;
        PrintMapInfo(playground);
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

        PlayerCaptureState@ state = FindPlayerState(player);
        if (state is null) {
            @state = StartPlayerIfActive(
                playground, raceData, racePlayer, player, scriptPlayer, playerIndex
            );
            if (state is null) return false;
        } else if (racePlayer.StartTime > state.MlStartTime) {
            EndRestartedAttempt(state);
            return true;
        }

        CaptureEvents(playground, raceData, racePlayer, scriptPlayer, state);
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
        Attempt.AttemptId = MapUid(CurrentMap) + "-" + Time::Stamp + "-" + Attempt.Ordinal;
        print("[" + PluginInfo::Name + "] ATTEMPT_STARTED id=" + Attempt.AttemptId +
            " timing=mlfeed_game_clock");
    }

    void CaptureEvents(
        CSmArenaClient@ playground,
        const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
        const MLFeed::PlayerCpInfo_V4@ racePlayer,
        CSmScriptPlayer@ scriptPlayer,
        PlayerCaptureState@ state
    )
    {
        SnapshotPlayerTelemetry(racePlayer, state);
        CaptureVehicle(playground, state);
        CaptureRespawns(racePlayer, state);
        CaptureCheckpoints(raceData, racePlayer, state);
        CaptureFirstThrottle(racePlayer, scriptPlayer, state);
    }

    void CaptureVehicle(CSmArenaClient@ playground, PlayerCaptureState@ state)
    {
        string vehicleType = ResolveVehicleType(playground, state.Player);
        if (vehicleType.Length == 0) {
            if (state.LastObservedVehicleType.Length > 0) {
                state.EndVehicleType = state.LastObservedVehicleType;
            } else if (state.EndVehicleType.Length == 0) {
                state.EndVehicleType = UnknownVehicleType;
            }
            return;
        }

        if (state.StartVehicleType.Length == 0) state.StartVehicleType = vehicleType;
        state.EndVehicleType = vehicleType;

        bool changed = state.LastObservedVehicleType.Length > 0 &&
            state.LastObservedVehicleType != vehicleType;
        state.LastObservedVehicleType = vehicleType;
        AddVehicleSeen(state, vehicleType);
        if (changed) AddVehicleChangedEvent(state, vehicleType);
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

    void AddVehicleChangedEvent(PlayerCaptureState@ state, const string &in vehicleType)
    {
        RaceEventCapture@ event = NewEvent(state, "vehicle_changed", state.LastRaceTimeMs);
        event.VehicleType = vehicleType;
        state.Events.InsertLast(event);
        print("[" + PluginInfo::Name + "] VEHICLE_CHANGED key=" + state.ParticipantKey +
            " type=" + vehicleType + " durationMs=" + state.LastRaceTimeMs);
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

    PlayerCaptureState@ FindPlayerState(CSmPlayer@ player)
    {
        for (uint i = 0; i < Players.Length; i++) {
            if (Players[i].Player is player) return Players[i];
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
        @state.Player = player;
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
        state.EndVehicleType = UnknownVehicleType;
        if (Attempt.Active && state.StartedAtUtcMs < Attempt.StartedAtUtcMs) {
            Attempt.StartedAtUtcMs = state.StartedAtUtcMs;
        }
        return state;
    }

    void AddVehicleSeen(PlayerCaptureState@ state, const string &in vehicleType)
    {
        for (uint i = 0; i < state.VehiclesSeen.Length; i++) {
            if (state.VehiclesSeen[i] == vehicleType) return;
        }
        state.VehiclesSeen.InsertLast(vehicleType);
    }

    string ResolveVehicleType(CSmArenaClient@ playground, CSmPlayer@ player)
    {
        if (playground is null || player is null) return "";

        CTrackMania@ app = cast<CTrackMania>(GetApp());
        if (app is null || app.GameScene is null) return "";

        auto vis = VehicleState::GetVis(app.GameScene, player);
        if (vis is null || vis.AsyncState is null) return "";

        return NormalizeVehicleType(VehicleState::GetVehicleType(vis.AsyncState));
    }

    string NormalizeVehicleType(VehicleState::VehicleType vehicleType)
    {
        if (vehicleType == 0) return "stadium";
        if (vehicleType == 1) return "snow";
        if (vehicleType == 2) return "rally";
        if (vehicleType == 3) return "desert";
        return UnknownVehicleType;
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

    string MapUid(CGameCtnChallenge@ map)
    {
        return map is null ? "" : map.EdChallengeId;
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
        print("[" + PluginInfo::Name + "] MAP uid=" + MapUid(playground.Map) +
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
