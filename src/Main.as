const string PluginName = Meta::ExecutingPlugin().Name;
const string PluginVersion = Meta::ExecutingPlugin().Version;
const float AcceleratorThreshold = 0.01f;

[Setting category="Webhook" name="Enabled" description="Send one webhook when a local race attempt ends."]
bool Setting_WebhookEnabled = false;

[Setting category="Webhook" name="Endpoint" description="HTTPS endpoint that receives race.attempt.ended JSON payloads."]
string Setting_WebhookEndpoint = "";

[Setting category="Webhook" name="API key" description="Sent in the X-API-Key request header." password=true]
string Setting_WebhookApiKey = "";

[Setting category="Webhook" name="Retry count" description="Number of retries after the initial request." min=0 max=5]
uint Setting_WebhookRetryCount = 3;

class RaceEventCapture
{
    uint Sequence;
    string Type;
    string AtUtc;
    int DurationMs;
    int CheckpointIndex = -1;
    int Lap = -1;
    int LapCheckpointIndex = -1;
    int SplitDurationMs = -1;
    int TheoreticalDurationMs = -1;
    int RespawnCountAtCheckpoint = -1;
    int TimeLostToRespawnsMs = -1;
    int RespawnOrdinal = -1;
}

class PlayerCaptureState
{
    CSmPlayer@ Player;
    uint PlayerIndex;
    int TerminalIndex = -1;
    string ParticipantKey;
    string Login;
    string AccountId;
    string Name;
    bool IsFake = false;
    bool IsBot = false;
    int SpawnIndex = -1;
    uint MlStartTime = 0;
    int64 StartedAtUtcMs = 0;
    int LastCapturedCp = 0;
    int LastCheckpointDurationMs = 0;
    int LastRaceTimeMs = 0;
    bool IsLocalPlayer = false;
    int CurrentLap = -1;
    int CheckpointsPassed = 0;
    int FinalRaceTimeMs = -1;
    int TheoreticalRaceTimeMs = -1;
    int SessionBestTimeMs = -1;
    int RaceRank = -1;
    int RaceRespawnRank = -1;
    int TimeAttackRank = -1;
    int RespawnCount = 0;
    int CapturedRespawnEvents = 0;
    int RespawnTimeLostMs = 0;
    int LastRespawnCheckpoint = -1;
    int LastRespawnDurationMs = -1;
    float LatencyEstimateMs = 0.0f;
    float LatencySampleCount = 0.0f;
    array<uint> BestRaceTimes;
    array<uint> BestLapTimes;
    bool AcceleratorRecorded = false;
    bool Finished = false;
    int FinishPosition = -1;
    string Outcome = "unknown";
    string FirstAcceleratorAtUtc;
    int FirstAcceleratorDurationMs = -1;
    array<RaceEventCapture@> Events;
}

class RaceAttemptState
{
    bool Active = false;
    string AttemptId;
    int64 StartedAtUtcMs = 0;
    uint Ordinal = 0;
    int CheckpointsPerLap = -1;
    int WaypointsToFinish = -1;
    int MlFeedLapCount = -1;
}

class WebhookJob
{
    string EventId;
    string Body;
}

array<PlayerCaptureState@> PlayerStates;
array<WebhookJob@> WebhookQueue;
CGameCtnChallenge@ CurrentMap;
RaceAttemptState@ Attempt = RaceAttemptState();
bool PlaygroundWasAvailable = false;
bool AwaitingAttemptReset = false;
uint AttemptOrdinal = 0;
int64 UtcAnchorEpochMs = 0;
uint64 UtcAnchorMonotonicMs = 0;

void Main()
{
    UtcAnchorEpochMs = Time::Stamp * 1000;
    UtcAnchorMonotonicMs = Time::Now;
    startnew(CalibrateUtcClock);
    print("[" + PluginName + "] Race webhook capture loaded with MLFeed game timing.");

    while (true) {
        if (WebhookQueue.Length > 0) DeliverNextWebhook();
        yield();
    }
}

void CalibrateUtcClock()
{
    int64 previousStamp = Time::Stamp;
    while (Time::Stamp == previousStamp) yield();
    UtcAnchorEpochMs = Time::Stamp * 1000;
    UtcAnchorMonotonicMs = Time::Now;
}

void Update(float dt)
{
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    if (app is null) return;

    CSmArenaClient@ playground = cast<CSmArenaClient>(app.CurrentPlayground);
    if (playground is null) {
        if (PlaygroundWasAvailable) {
            EndAttempt("playground_closed", "quit");
            ClearCaptureState();
            PlaygroundWasAvailable = false;
        }
        return;
    }

    PlaygroundWasAvailable = true;
    if (CurrentMap !is playground.Map) {
        EndAttempt("map_changed", "dnf");
        @CurrentMap = playground.Map;
        PlayerStates.RemoveRange(0, PlayerStates.Length);
        ResetAttempt();
        AwaitingAttemptReset = false;
        PrintMapInfo(playground);
    }

    const MLFeed::HookRaceStatsEventsBase_V4@ raceData = MLFeed::GetRaceData_V4();
    if (raceData is null || raceData.Map.Length == 0) return;

    for (uint i = 0; i < playground.Players.Length; i++) {
        CSmPlayer@ player = cast<CSmPlayer>(playground.Players[i]);
        if (player is null || player.ScriptAPI is null) continue;

        CSmScriptPlayer@ scriptPlayer = cast<CSmScriptPlayer>(player.ScriptAPI);
        if (scriptPlayer is null) continue;

        const MLFeed::PlayerCpInfo_V4@ racePlayer = FindRacePlayer(raceData, player, scriptPlayer);
        if (racePlayer is null || racePlayer.StartTime == 0) continue;

        PlayerCaptureState@ state = FindPlayerState(player);
        if (state is null) {
            if (AwaitingAttemptReset) continue;
            @state = CreatePlayerState(playground, i, player, scriptPlayer, racePlayer);
            PlayerStates.InsertLast(state);
            EnsureAttemptStarted(raceData, racePlayer);
            AddStartEvent(state);
            print("[" + PluginName + "] PLAYER_STARTED key=" + state.ParticipantKey +
                " gameStartTime=" + state.MlStartTime);
        } else if (racePlayer.StartTime > state.MlStartTime) {
            state.LastRaceTimeMs = Math::Max(
                state.LastRaceTimeMs,
                int(MLFeed::GameTime) - int(state.MlStartTime)
            );
            state.FinalRaceTimeMs = state.LastRaceTimeMs;
            EndAttempt("restart", "restart");
            PlayerStates.RemoveRange(0, PlayerStates.Length);
            ResetAttempt();
            AwaitingAttemptReset = false;
            return;
        }

        CapturePlayerEvents(raceData, racePlayer, scriptPlayer, state);
    }

    if (Attempt.Active && AllPlayersFinished(playground)) {
        EndAttempt("all_finished", "finished");
    }
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
    if (name.Length == 0 && player.User !is null) name = Text::StripFormatCodes(player.User.Name);
    if (name.Length == 0) return null;
    return raceData.GetPlayer_V4(name);
}

void EnsureAttemptStarted(
    const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
    const MLFeed::PlayerCpInfo_V4@ racePlayer
)
{
    if (CurrentMap is null) return;

    SnapshotRaceConfiguration(raceData);
    if (Attempt.Active) return;

    Attempt.Active = true;
    Attempt.Ordinal = ++AttemptOrdinal;
    Attempt.StartedAtUtcMs = CurrentUtcMs() - racePlayer.CurrentRaceTimeRaw;
    Attempt.AttemptId = GetMapUid(CurrentMap) + "-" + Time::Stamp + "-" + Attempt.Ordinal;
    print("[" + PluginName + "] ATTEMPT_STARTED id=" + Attempt.AttemptId +
        " timing=mlfeed_game_clock");
}

void SnapshotRaceConfiguration(const MLFeed::HookRaceStatsEventsBase_V4@ raceData)
{
    Attempt.CheckpointsPerLap = int(raceData.CPCount);
    Attempt.WaypointsToFinish = int(raceData.CPsToFinish);
    Attempt.MlFeedLapCount = int(raceData.LapCount_Accurate);
}

void CapturePlayerEvents(
    const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
    const MLFeed::PlayerCpInfo_V4@ racePlayer,
    CSmScriptPlayer@ scriptPlayer,
    PlayerCaptureState@ state
)
{
    SnapshotPlayerTelemetry(racePlayer, state);
    CaptureRespawnEvents(racePlayer, state);

    while (state.LastCapturedCp < racePlayer.CpCount) {
        int nextCp = state.LastCapturedCp + 1;
        if (uint(nextCp) >= racePlayer.CpTimes.Length) break;

        int checkpointTime = racePlayer.CpTimes[nextCp];
        if (checkpointTime <= 0) break;

        bool isFinish = uint(nextCp) == raceData.CPsToFinish;
        AddCheckpointEvent(state, raceData, racePlayer, nextCp, checkpointTime, isFinish);
        state.LastCapturedCp = nextCp;

        if (isFinish) {
            state.Finished = true;
            state.Outcome = "finished";
        }
    }

    if (!state.Finished && racePlayer.IsFinished && racePlayer.LastCpTime > 0) {
        AddCheckpointEvent(
            state,
            raceData,
            racePlayer,
            racePlayer.CpCount,
            racePlayer.LastCpTime,
            true
        );
        state.LastCapturedCp = racePlayer.CpCount;
        state.Finished = true;
        state.Outcome = "finished";
    }

    if (!state.AcceleratorRecorded && racePlayer.CurrentRaceTimeRaw >= 0 &&
        scriptPlayer.InputGasPedal > AcceleratorThreshold) {
        state.AcceleratorRecorded = true;
        state.FirstAcceleratorDurationMs = racePlayer.CurrentRaceTimeRaw;
        state.FirstAcceleratorAtUtc = EventUtc(state, state.FirstAcceleratorDurationMs);
        print("[" + PluginName + "] FIRST_ACCELERATOR key=" + state.ParticipantKey +
            " durationMs=" + state.FirstAcceleratorDurationMs);
    }
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
    state.CurrentLap = int(racePlayer.CurrentLap);
    state.CheckpointsPassed = racePlayer.CpCount;
    state.FinalRaceTimeMs = racePlayer.IsFinished
        ? racePlayer.LastCpTime : Math::Max(racePlayer.CurrentRaceTimeRaw, 0);
    state.TheoreticalRaceTimeMs = racePlayer.IsFinished
        ? racePlayer.LastTheoreticalCpTime : Math::Max(racePlayer.TheoreticalRaceTime, 0);
    state.SessionBestTimeMs = racePlayer.BestTime > 0 ? racePlayer.BestTime : -1;
    state.RaceRank = racePlayer.RaceRank > 0 ? int(racePlayer.RaceRank) : -1;
    state.RaceRespawnRank = racePlayer.RaceRespawnRank > 0 ? int(racePlayer.RaceRespawnRank) : -1;
    state.TimeAttackRank = racePlayer.TaRank > 0 ? int(racePlayer.TaRank) : -1;
    state.RespawnTimeLostMs = int(racePlayer.TimeLostToRespawns);
    state.LastRespawnCheckpoint = racePlayer.NbRespawnsRequested > 0
        ? int(racePlayer.LastRespawnCheckpoint) : -1;
    state.LastRespawnDurationMs = racePlayer.NbRespawnsRequested > 0
        ? int(racePlayer.LastRespawnRaceTime) : -1;
    state.LatencyEstimateMs = racePlayer.latencyEstimate;
    state.LatencySampleCount = racePlayer.lagDataPoints;

    state.BestRaceTimes.RemoveRange(0, state.BestRaceTimes.Length);
    if (racePlayer.BestRaceTimes !is null) {
        for (uint i = 0; i < racePlayer.BestRaceTimes.Length; i++) {
            state.BestRaceTimes.InsertLast(racePlayer.BestRaceTimes[i]);
        }
    }

    state.BestLapTimes.RemoveRange(0, state.BestLapTimes.Length);
    if (racePlayer.BestLapTimes !is null) {
        for (uint i = 0; i < racePlayer.BestLapTimes.Length; i++) {
            state.BestLapTimes.InsertLast(racePlayer.BestLapTimes[i]);
        }
    }
}

void CaptureRespawnEvents(
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
        int cumulativeTimeLostMs = isNewest ? int(racePlayer.TimeLostToRespawns) : -1;
        AddRespawnEvent(
            state,
            int(captured + 1),
            respawnTimes[captured],
            checkpointIndex,
            cumulativeTimeLostMs
        );
        captured++;
    }

    state.CapturedRespawnEvents = int(captured);
    state.RespawnCount = int(requested);
}

void AddStartEvent(PlayerCaptureState@ state)
{
    RaceEventCapture@ event = RaceEventCapture();
    event.Sequence = state.Events.Length;
    event.Type = "start";
    event.DurationMs = 0;
    event.AtUtc = EventUtc(state, 0);
    state.Events.InsertLast(event);
}

void AddCheckpointEvent(
    PlayerCaptureState@ state,
    const MLFeed::HookRaceStatsEventsBase_V4@ raceData,
    const MLFeed::PlayerCpInfo_V4@ racePlayer,
    int checkpointIndex,
    int durationMs,
    bool isFinish
)
{
    RaceEventCapture@ event = RaceEventCapture();
    event.Sequence = state.Events.Length;
    event.Type = isFinish ? "finish" : "checkpoint";
    event.DurationMs = durationMs;
    event.AtUtc = EventUtc(state, durationMs);
    event.CheckpointIndex = checkpointIndex;
    event.SplitDurationMs = durationMs - state.LastCheckpointDurationMs;
    state.LastCheckpointDurationMs = durationMs;

    if (racePlayer.TimeLostToRespawnByCp !is null) {
        event.TimeLostToRespawnsMs = CumulativeTimeLostAtCheckpoint(
            racePlayer.TimeLostToRespawnByCp,
            checkpointIndex
        );
        event.TheoreticalDurationMs = durationMs - event.TimeLostToRespawnsMs;
    }
    if (racePlayer.NbRespawnsByCp !is null &&
        uint(checkpointIndex) < racePlayer.NbRespawnsByCp.Length) {
        event.RespawnCountAtCheckpoint = racePlayer.NbRespawnsByCp[checkpointIndex];
    }

    int checkpointsPerLap = int(raceData.CPCount) + 1;
    if (checkpointsPerLap > 0) {
        event.Lap = ((checkpointIndex - 1) / checkpointsPerLap) + 1;
        event.LapCheckpointIndex = ((checkpointIndex - 1) % checkpointsPerLap) + 1;
    }
    state.Events.InsertLast(event);

    print("[" + PluginName + "] " + event.Type.ToUpper() +
        " key=" + state.ParticipantKey + " checkpoint=" + checkpointIndex +
        " durationMs=" + durationMs);
}

int CumulativeTimeLostAtCheckpoint(const array<int>@ losses, int checkpointIndex)
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
    int checkpointIndex,
    int cumulativeTimeLostMs
)
{
    RaceEventCapture@ event = RaceEventCapture();
    event.Sequence = state.Events.Length;
    event.Type = "respawn";
    event.DurationMs = Math::Max(durationMs, 0);
    event.AtUtc = EventUtc(state, event.DurationMs);
    event.RespawnOrdinal = ordinal;
    event.CheckpointIndex = checkpointIndex;
    event.TimeLostToRespawnsMs = cumulativeTimeLostMs;
    state.Events.InsertLast(event);

    print("[" + PluginName + "] RESPAWN key=" + state.ParticipantKey +
        " ordinal=" + ordinal + " durationMs=" + durationMs);
}

void AddTerminalEvent(PlayerCaptureState@ state, const string &in type, int durationMs)
{
    RaceEventCapture@ event = RaceEventCapture();
    event.Sequence = state.Events.Length;
    event.Type = type;
    event.DurationMs = Math::Max(durationMs, 0);
    event.AtUtc = EventUtc(state, event.DurationMs);
    state.Events.InsertLast(event);
}

PlayerCaptureState@ FindPlayerState(CSmPlayer@ player)
{
    for (uint i = 0; i < PlayerStates.Length; i++) {
        if (PlayerStates[i].Player is player) return PlayerStates[i];
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
    if (state.Login.Length == 0 && player.User !is null) state.Login = player.User.Login;
    if (state.Name.Length == 0 && player.User !is null) {
        state.Name = Text::StripFormatCodes(player.User.Name);
    }
    state.ParticipantKey = state.AccountId.Length > 0 ? state.AccountId :
        (state.Login.Length > 0 ? state.Login :
            "local-player-" + playerIndex + "-terminal-" + state.TerminalIndex);
    state.IsFake = scriptPlayer.IsFakePlayer;
    state.IsBot = scriptPlayer.IsBot;
    state.SpawnIndex = int(racePlayer.SpawnIndex);
    state.MlStartTime = racePlayer.StartTime;
    state.LastRaceTimeMs = Math::Max(racePlayer.CurrentRaceTimeRaw, 0);
    state.StartedAtUtcMs = CurrentUtcMs() - state.LastRaceTimeMs;
    if (Attempt.Active && state.StartedAtUtcMs < Attempt.StartedAtUtcMs) {
        Attempt.StartedAtUtcMs = state.StartedAtUtcMs;
    }
    return state;
}

bool AllPlayersFinished(CSmArenaClient@ playground)
{
    if (PlayerStates.Length == 0 || PlayerStates.Length < playground.Players.Length) return false;
    for (uint i = 0; i < PlayerStates.Length; i++) {
        if (!PlayerStates[i].Finished) return false;
    }
    return true;
}

void EndAttempt(const string &in endReason, const string &in unfinishedOutcome)
{
    if (!Attempt.Active || CurrentMap is null || PlayerStates.Length == 0) return;

    for (uint i = 0; i < PlayerStates.Length; i++) {
        PlayerCaptureState@ state = PlayerStates[i];
        if (!state.Finished) {
            state.Outcome = unfinishedOutcome;
            AddTerminalEvent(state, unfinishedOutcome, state.LastRaceTimeMs);
        }
    }

    ComputeFinishPositions();
    int durationMs = AttemptDurationMs();
    string endedAtUtc = FormatUtcMs(Attempt.StartedAtUtcMs + durationMs);
    Json::Value@ payload = BuildPayload(endReason, endedAtUtc, durationMs);
    string body = Json::Write(payload);
    print("[" + PluginName + "] ATTEMPT_ENDED id=" + Attempt.AttemptId +
        " reason=" + endReason + " durationMs=" + durationMs);

    if (Setting_WebhookEnabled && Setting_WebhookEndpoint.Length > 0) {
        WebhookJob@ job = WebhookJob();
        job.EventId = Attempt.AttemptId;
        job.Body = body;
        WebhookQueue.InsertLast(job);
    } else {
        print("[" + PluginName + "] WEBHOOK_SKIPPED disabled or endpoint missing");
    }

    Attempt.Active = false;
    AwaitingAttemptReset = true;
}

void ComputeFinishPositions()
{
    for (uint i = 0; i < PlayerStates.Length; i++) {
        PlayerCaptureState@ player = PlayerStates[i];
        if (!player.Finished) continue;

        int finishTime = LastEventDuration(player);
        int position = 1;
        for (uint j = 0; j < PlayerStates.Length; j++) {
            PlayerCaptureState@ other = PlayerStates[j];
            if (!other.Finished || other is player) continue;
            int otherTime = LastEventDuration(other);
            if (otherTime < finishTime ||
                (otherTime == finishTime && other.PlayerIndex < player.PlayerIndex)) position++;
        }
        player.FinishPosition = position;
    }
}

int AttemptDurationMs()
{
    int64 endedAtUtcMs = Attempt.StartedAtUtcMs;
    for (uint i = 0; i < PlayerStates.Length; i++) {
        int64 playerEndedAtUtcMs = PlayerStates[i].StartedAtUtcMs + LastEventDuration(PlayerStates[i]);
        if (playerEndedAtUtcMs > endedAtUtcMs) endedAtUtcMs = playerEndedAtUtcMs;
    }
    return int(endedAtUtcMs - Attempt.StartedAtUtcMs);
}

int LastEventDuration(PlayerCaptureState@ state)
{
    if (state.Events.Length == 0) return state.LastRaceTimeMs;
    return state.Events[state.Events.Length - 1].DurationMs;
}

Json::Value@ BuildPayload(
    const string &in endReason,
    const string &in endedAtUtc,
    int durationMs
)
{
    Json::Value@ root = Json::Object();
    root["schemaVersion"] = "1.1";
    root["eventType"] = "race.attempt.ended";
    root["eventId"] = Attempt.AttemptId;
    root["occurredAtUtc"] = endedAtUtc;

    Json::Value@ source = Json::Object();
    source["pluginName"] = PluginName;
    source["pluginVersion"] = PluginVersion;
    source["game"] = "Trackmania";
    root["source"] = source;

    Json::Value@ attempt = Json::Object();
    attempt["attemptId"] = Attempt.AttemptId;
    attempt["format"] = PlayerStates.Length > 1 ? "split_screen" : "solo";
    attempt["playerCount"] = PlayerStates.Length;
    attempt["startedAtUtc"] = FormatUtcMs(Attempt.StartedAtUtcMs);
    attempt["endedAtUtc"] = endedAtUtc;
    attempt["durationMs"] = durationMs;
    attempt["endReason"] = endReason;
    attempt["timingSource"] = "mlfeed_game_clock";
    attempt["map"] = BuildMapJson(CurrentMap);

    Json::Value@ players = Json::Array();
    for (uint i = 0; i < PlayerStates.Length; i++) players.Add(BuildPlayerJson(PlayerStates[i]));
    attempt["players"] = players;
    root["attempt"] = attempt;
    return root;
}

Json::Value@ BuildMapJson(CGameCtnChallenge@ map)
{
    Json::Value@ json = Json::Object();
    json["uid"] = GetMapUid(map);
    json["name"] = Text::StripFormatCodes(map.MapName);
    json["authorLogin"] = map.AuthorLogin;
    json["authorName"] = Text::StripFormatCodes(map.AuthorNickName);
    json["mapType"] = Text::StripFormatCodes(map.MapType);
    json["mapStyle"] = Text::StripFormatCodes(map.MapStyle);
    json["laps"] = map.TMObjective_NbLaps;
    json["isLapRace"] = map.TMObjective_IsLapRace;
    SetNullableInt(json, "checkpointsPerLap", Attempt.CheckpointsPerLap);
    SetNullableInt(json, "waypointsToFinish", Attempt.WaypointsToFinish);
    SetNullableInt(json, "mlFeedLapCount", Attempt.MlFeedLapCount);

    Json::Value@ medals = Json::Object();
    medals["author"] = map.TMObjective_AuthorTime;
    medals["gold"] = map.TMObjective_GoldTime;
    medals["silver"] = map.TMObjective_SilverTime;
    medals["bronze"] = map.TMObjective_BronzeTime;
    json["medalTimesMs"] = medals;
    return json;
}

Json::Value@ BuildPlayerJson(PlayerCaptureState@ state)
{
    Json::Value@ json = Json::Object();
    json["participantKey"] = state.ParticipantKey;
    json["playerIndex"] = state.PlayerIndex;
    json["terminalIndex"] = state.TerminalIndex;
    json["login"] = state.Login;
    if (state.AccountId.Length > 0) json["accountId"] = state.AccountId;
    else json["accountId"] = Json::Parse("null");
    json["name"] = state.Name;
    json["isFake"] = state.IsFake;
    json["isBot"] = state.IsBot;
    json["isLocalPlayer"] = state.IsLocalPlayer;
    json["spawnIndex"] = state.SpawnIndex;
    if (state.FinishPosition >= 0) json["finishPosition"] = state.FinishPosition;
    else json["finishPosition"] = Json::Parse("null");
    json["outcome"] = state.Outcome;
    SetNullableInt(json, "currentLap", state.CurrentLap);
    json["checkpointsPassed"] = state.CheckpointsPassed;
    SetNullableInt(json, "finalRaceTimeMs", state.FinalRaceTimeMs);
    SetNullableInt(json, "theoreticalRaceTimeMs", state.TheoreticalRaceTimeMs);
    SetNullableInt(json, "sessionBestTimeMs", state.SessionBestTimeMs);

    Json::Value@ ranks = Json::Object();
    SetNullableInt(ranks, "race", state.RaceRank);
    SetNullableInt(ranks, "raceWithRespawns", state.RaceRespawnRank);
    SetNullableInt(ranks, "timeAttack", state.TimeAttackRank);
    json["ranks"] = ranks;

    Json::Value@ respawns = Json::Object();
    respawns["count"] = state.RespawnCount;
    respawns["timeLostMs"] = state.RespawnTimeLostMs;
    SetNullableInt(respawns, "lastCheckpointIndex", state.LastRespawnCheckpoint);
    SetNullableInt(respawns, "lastAtDurationMs", state.LastRespawnDurationMs);
    json["respawns"] = respawns;

    Json::Value@ timingDiagnostics = Json::Object();
    if (state.LatencySampleCount > 0.0f) {
        timingDiagnostics["latencyEstimateMs"] = state.LatencyEstimateMs;
        timingDiagnostics["latencySampleCount"] = state.LatencySampleCount;
    } else {
        timingDiagnostics["latencyEstimateMs"] = Json::Parse("null");
        timingDiagnostics["latencySampleCount"] = Json::Parse("null");
    }
    json["timingDiagnostics"] = timingDiagnostics;

    Json::Value@ sessionBest = Json::Object();
    sessionBest["raceCheckpointTimesMs"] = UIntArrayJson(state.BestRaceTimes);
    sessionBest["raceIsComplete"] = Attempt.WaypointsToFinish >= 0 &&
        state.BestRaceTimes.Length >= uint(Attempt.WaypointsToFinish + 1);
    sessionBest["lapCheckpointTimesMs"] = UIntArrayJson(state.BestLapTimes);
    sessionBest["lapIsComplete"] = Attempt.CheckpointsPerLap >= 0 &&
        state.BestLapTimes.Length >= uint(Attempt.CheckpointsPerLap + 2);
    json["sessionBest"] = sessionBest;

    if (state.AcceleratorRecorded) {
        Json::Value@ accelerator = Json::Object();
        accelerator["atUtc"] = state.FirstAcceleratorAtUtc;
        accelerator["durationMs"] = state.FirstAcceleratorDurationMs;
        json["firstAccelerator"] = accelerator;
    } else {
        json["firstAccelerator"] = Json::Parse("null");
    }

    Json::Value@ events = Json::Array();
    array<RaceEventCapture@> orderedEvents = OrderedEvents(state.Events);
    for (uint i = 0; i < orderedEvents.Length; i++) {
        RaceEventCapture@ event = orderedEvents[i];
        Json::Value@ item = Json::Object();
        item["sequence"] = i;
        item["type"] = event.Type;
        item["atUtc"] = event.AtUtc;
        item["durationMs"] = event.DurationMs;
        if (event.Type == "checkpoint" || event.Type == "finish") {
            Json::Value@ checkpoint = Json::Object();
            checkpoint["index"] = event.CheckpointIndex;
            checkpoint["lap"] = event.Lap;
            checkpoint["lapCheckpointIndex"] = event.LapCheckpointIndex;
            item["checkpoint"] = checkpoint;
            SetNullableInt(item, "splitDurationMs", event.SplitDurationMs);
            SetNullableInt(item, "theoreticalDurationMs", event.TheoreticalDurationMs);
            SetNullableInt(item, "respawnCountAtCheckpoint", event.RespawnCountAtCheckpoint);
            SetNullableInt(item, "timeLostToRespawnsMs", event.TimeLostToRespawnsMs);
        } else if (event.Type == "respawn") {
            Json::Value@ respawn = Json::Object();
            respawn["ordinal"] = event.RespawnOrdinal;
            SetNullableInt(respawn, "checkpointIndex", event.CheckpointIndex);
            SetNullableInt(respawn, "timeLostToRespawnsMs", event.TimeLostToRespawnsMs);
            item["respawn"] = respawn;
        }
        events.Add(item);
    }
    json["events"] = events;
    return json;
}

void SetNullableInt(Json::Value@ object, const string &in key, int value)
{
    if (value >= 0) object[key] = value;
    else object[key] = Json::Parse("null");
}

Json::Value@ UIntArrayJson(const array<uint>@ values)
{
    Json::Value@ json = Json::Array();
    for (uint i = 0; i < values.Length; i++) json.Add(values[i]);
    return json;
}

array<RaceEventCapture@> OrderedEvents(const array<RaceEventCapture@>@ events)
{
    array<RaceEventCapture@> ordered;
    for (uint i = 0; i < events.Length; i++) ordered.InsertLast(events[i]);

    for (uint i = 1; i < ordered.Length; i++) {
        RaceEventCapture@ candidate = ordered[i];
        int j = int(i) - 1;
        while (j >= 0 && EventComesBefore(candidate, ordered[j])) {
            @ordered[j + 1] = ordered[j];
            j--;
        }
        @ordered[j + 1] = candidate;
    }
    return ordered;
}

bool EventComesBefore(RaceEventCapture@ left, RaceEventCapture@ right)
{
    if (left.DurationMs != right.DurationMs) return left.DurationMs < right.DurationMs;
    int leftPriority = EventTypePriority(left.Type);
    int rightPriority = EventTypePriority(right.Type);
    if (leftPriority != rightPriority) return leftPriority < rightPriority;
    return left.Sequence < right.Sequence;
}

int EventTypePriority(const string &in type)
{
    if (type == "start") return 0;
    if (type == "checkpoint") return 1;
    if (type == "respawn") return 2;
    return 3;
}

void DeliverNextWebhook()
{
    WebhookJob@ job = WebhookQueue[0];
    uint maxAttempts = Setting_WebhookRetryCount + 1;

    for (uint attemptNumber = 1; attemptNumber <= maxAttempts; attemptNumber++) {
        auto request = Net::HttpRequest();
        request.Method = Net::HttpMethod::Post;
        request.Url = Setting_WebhookEndpoint;
        request.Headers["Content-Type"] = "application/json";
        if (Setting_WebhookApiKey.Length > 0) request.Headers["X-API-Key"] = Setting_WebhookApiKey;
        request.Body = job.Body;
        request.Start();
        while (!request.Finished()) yield();

        int status = request.ResponseCode();
        if (status >= 200 && status < 300) {
            print("[" + PluginName + "] WEBHOOK_DELIVERED id=" + job.EventId + " status=" + status);
            WebhookQueue.RemoveAt(0);
            return;
        }

        warn("[" + PluginName + "] WEBHOOK_FAILED id=" + job.EventId +
            " attempt=" + attemptNumber + " status=" + status);
        if (attemptNumber < maxAttempts) sleep(RetryDelayMs(attemptNumber));
    }

    error("[" + PluginName + "] WEBHOOK_DROPPED id=" + job.EventId +
        " after=" + maxAttempts + " attempts");
    WebhookQueue.RemoveAt(0);
}

uint RetryDelayMs(uint attemptNumber)
{
    if (attemptNumber == 1) return 1000;
    if (attemptNumber == 2) return 3000;
    return 10000;
}

int64 CurrentUtcMs()
{
    return UtcAnchorEpochMs + int64(Time::Now - UtcAnchorMonotonicMs);
}

string EventUtc(PlayerCaptureState@ state, int durationMs)
{
    return FormatUtcMs(state.StartedAtUtcMs + durationMs);
}

string FormatUtcMs(int64 epochMs)
{
    int64 seconds = epochMs / 1000;
    int milliseconds = int(epochMs % 1000);
    if (milliseconds < 0) milliseconds += 1000;
    return Time::FormatStringUTC("%Y-%m-%dT%H:%M:%S", seconds) +
        "." + Text::Format("%03d", milliseconds) + "Z";
}

string GetMapUid(CGameCtnChallenge@ map)
{
    if (map is null) return "";
    return map.EdChallengeId;
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
    print("[" + PluginName + "] MAP uid=" + GetMapUid(playground.Map) +
        " name=\"" + Text::StripFormatCodes(playground.Map.MapName) + "\"" +
        " players=" + playground.Players.Length + " terminals=" + playground.GameTerminals.Length);
}

void ResetAttempt()
{
    @Attempt = RaceAttemptState();
}

void ClearCaptureState()
{
    PlayerStates.RemoveRange(0, PlayerStates.Length);
    @CurrentMap = null;
    ResetAttempt();
    AwaitingAttemptReset = false;
}

void OnDestroyed()
{
    print("[" + PluginName + "] Race webhook capture unloaded.");
}
