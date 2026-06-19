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

class CheckpointCapture
{
    uint Sequence;
    uint LandmarkIndex;
    int LandmarkOrder;
    string LandmarkTag;
    string Kind;
    string AtUtc;
    uint64 ElapsedMs;
}

class PlayerCaptureState
{
    CSmPlayer@ Player;
    int StartTime = -1;
    uint LastLandmarkIndex = uint(-1);
    bool AcceleratorRecorded = false;
    bool Finished = false;
    uint PlayerIndex;
    int TerminalIndex = -1;
    string ParticipantKey;
    string Login;
    string Name;
    bool IsFake = false;
    bool IsBot = false;
    int SpawnIndex = -1;
    int FinishPosition = -1;
    string Outcome = "unknown";
    string FirstAcceleratorAtUtc;
    int64 FirstAcceleratorElapsedMs = -1;
    array<CheckpointCapture@> Checkpoints;
}

class RaceAttemptState
{
    bool Active = false;
    string AttemptId;
    string StartedAtUtc;
    uint64 StartedAtMs = 0;
    uint FinishCount = 0;
    uint Ordinal = 0;
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

void Main()
{
    print("[" + PluginName + "] Race webhook capture loaded.");
    while (true) {
        if (WebhookQueue.Length > 0) DeliverNextWebhook();
        yield();
    }
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

    for (uint i = 0; i < playground.Players.Length; i++) {
        CSmPlayer@ player = cast<CSmPlayer>(playground.Players[i]);
        if (player is null || player.ScriptAPI is null) continue;

        CSmScriptPlayer@ data = cast<CSmScriptPlayer>(player.ScriptAPI);
        if (data is null) continue;

        PlayerCaptureState@ state = FindPlayerState(player);
        if (state is null) {
            @state = CreatePlayerState(playground, i, player, data);
            PlayerStates.InsertLast(state);
            print("[" + PluginName + "] PLAYER_FOUND key=" + state.ParticipantKey +
                " index=" + i + " terminal=" + state.TerminalIndex);
        }

        EnsureAttemptStarted(data);
        if (CapturePlayerEvents(playground, player, data, state)) return;
    }

    if (Attempt.Active && AllPlayersFinished(playground)) {
        EndAttempt("all_finished", "finished");
    }
}

void EnsureAttemptStarted(CSmScriptPlayer@ data)
{
    if (Attempt.Active || AwaitingAttemptReset || data.StartTime < 0 || CurrentMap is null) return;

    Attempt.Active = true;
    Attempt.Ordinal = ++AttemptOrdinal;
    Attempt.StartedAtMs = Time::Now;
    Attempt.StartedAtUtc = UtcNow();
    Attempt.AttemptId = GetMapUid(CurrentMap) + "-" + Time::Stamp + "-" + Attempt.Ordinal;
    print("[" + PluginName + "] ATTEMPT_STARTED id=" + Attempt.AttemptId + " timing=inferred");
}

bool CapturePlayerEvents(
    CSmArenaClient@ playground,
    CSmPlayer@ player,
    CSmScriptPlayer@ data,
    PlayerCaptureState@ state
)
{
    if (data.StartTime != state.StartTime) {
        if (AwaitingAttemptReset) {
            PlayerStates.RemoveRange(0, PlayerStates.Length);
            ResetAttempt();
            AwaitingAttemptReset = false;
            return true;
        }

        bool restarted = Attempt.Active && HasPlayerActivity(state) && data.StartTime >= 0;
        state.StartTime = data.StartTime;
        state.LastLandmarkIndex = player.CurrentLaunchedRespawnLandmarkIndex;
        if (restarted) {
            EndAttempt("restart", "restart");
            PlayerStates.RemoveRange(0, PlayerStates.Length);
            ResetAttempt();
            AwaitingAttemptReset = false;
            return true;
        }
    }

    CaptureLandmarkEvent(playground, player, state);

    if (Attempt.Active && !state.AcceleratorRecorded && data.InputGasPedal > AcceleratorThreshold) {
        state.AcceleratorRecorded = true;
        state.FirstAcceleratorAtUtc = UtcNow();
        state.FirstAcceleratorElapsedMs = int64(ElapsedMs());
        print("[" + PluginName + "] FIRST_ACCELERATOR key=" + state.ParticipantKey +
            " elapsedMs=" + state.FirstAcceleratorElapsedMs);
    }
    return false;
}

void CaptureLandmarkEvent(
    CSmArenaClient@ playground,
    CSmPlayer@ player,
    PlayerCaptureState@ state
)
{
    uint landmarkIndex = player.CurrentLaunchedRespawnLandmarkIndex;
    if (landmarkIndex == state.LastLandmarkIndex) return;

    state.LastLandmarkIndex = landmarkIndex;
    if (!Attempt.Active || landmarkIndex == uint(-1) || playground.Arena is null) return;
    if (landmarkIndex >= playground.Arena.MapLandmarks.Length) return;

    auto@ landmark = playground.Arena.MapLandmarks[landmarkIndex];
    if (landmark is null || landmark.Waypoint is null) return;

    CheckpointCapture@ checkpoint = CheckpointCapture();
    checkpoint.Sequence = state.Checkpoints.Length;
    checkpoint.LandmarkIndex = landmarkIndex;
    checkpoint.LandmarkOrder = landmark.Order;
    checkpoint.LandmarkTag = landmark.Tag;
    checkpoint.Kind = landmark.Waypoint.IsFinish ? "finish" :
        (landmark.Waypoint.IsMultiLap ? "lap_finish" : "checkpoint");
    checkpoint.AtUtc = UtcNow();
    checkpoint.ElapsedMs = ElapsedMs();
    state.Checkpoints.InsertLast(checkpoint);

    if (landmark.Waypoint.IsFinish && !state.Finished) {
        state.Finished = true;
        state.Outcome = "finished";
        state.FinishPosition = int(++Attempt.FinishCount);
    }

    print("[" + PluginName + "] " + checkpoint.Kind.ToUpper() +
        " key=" + state.ParticipantKey + " sequence=" + checkpoint.Sequence +
        " elapsedMs=" + checkpoint.ElapsedMs);
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
    CSmScriptPlayer@ data
)
{
    PlayerCaptureState@ state = PlayerCaptureState();
    @state.Player = player;
    state.StartTime = data.StartTime;
    state.LastLandmarkIndex = player.CurrentLaunchedRespawnLandmarkIndex;
    state.PlayerIndex = playerIndex;
    state.TerminalIndex = FindTerminalIndex(playground, player);
    state.Login = data.Login;
    state.Name = Text::StripFormatCodes(data.Name);
    if (state.Login.Length == 0 && player.User !is null) state.Login = player.User.Login;
    if (state.Name.Length == 0 && player.User !is null) {
        state.Name = Text::StripFormatCodes(player.User.Name);
    }
    state.ParticipantKey = state.Login.Length > 0 ? state.Login :
        "local-player-" + playerIndex + "-terminal-" + state.TerminalIndex;
    state.IsFake = data.IsFakePlayer;
    state.IsBot = data.IsBot;
    state.SpawnIndex = player.SpawnIndex;
    return state;
}

bool HasPlayerActivity(PlayerCaptureState@ state)
{
    return state.AcceleratorRecorded || state.Checkpoints.Length > 0;
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
        if (!PlayerStates[i].Finished) PlayerStates[i].Outcome = unfinishedOutcome;
    }

    string endedAtUtc = UtcNow();
    uint64 durationMs = ElapsedMs();
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

Json::Value@ BuildPayload(
    const string &in endReason,
    const string &in endedAtUtc,
    uint64 durationMs
)
{
    Json::Value@ root = Json::Object();
    root["schemaVersion"] = "1.0";
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
    attempt["startedAtUtc"] = Attempt.StartedAtUtc;
    attempt["endedAtUtc"] = endedAtUtc;
    attempt["durationMs"] = durationMs;
    attempt["endReason"] = endReason;
    attempt["timingSource"] = "inferred";
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
    json["accountId"] = Json::Parse("null");
    json["name"] = state.Name;
    json["isFake"] = state.IsFake;
    json["isBot"] = state.IsBot;
    json["spawnIndex"] = state.SpawnIndex;
    if (state.FinishPosition >= 0) json["finishPosition"] = state.FinishPosition;
    else json["finishPosition"] = Json::Parse("null");
    json["outcome"] = state.Outcome;

    if (state.AcceleratorRecorded) {
        Json::Value@ accelerator = Json::Object();
        accelerator["atUtc"] = state.FirstAcceleratorAtUtc;
        accelerator["elapsedMs"] = state.FirstAcceleratorElapsedMs;
        json["firstAccelerator"] = accelerator;
    } else {
        json["firstAccelerator"] = Json::Parse("null");
    }

    Json::Value@ checkpoints = Json::Array();
    for (uint i = 0; i < state.Checkpoints.Length; i++) {
        CheckpointCapture@ checkpoint = state.Checkpoints[i];
        Json::Value@ item = Json::Object();
        item["sequence"] = checkpoint.Sequence;
        item["landmarkIndex"] = checkpoint.LandmarkIndex;
        item["landmarkOrder"] = checkpoint.LandmarkOrder;
        item["landmarkTag"] = checkpoint.LandmarkTag;
        item["kind"] = checkpoint.Kind;
        item["atUtc"] = checkpoint.AtUtc;
        item["elapsedMs"] = checkpoint.ElapsedMs;
        checkpoints.Add(item);
    }
    json["checkpoints"] = checkpoints;
    return json;
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

uint64 ElapsedMs()
{
    if (!Attempt.Active || Time::Now < Attempt.StartedAtMs) return 0;
    return Time::Now - Attempt.StartedAtMs;
}

string UtcNow()
{
    return Time::FormatStringUTC("%Y-%m-%dT%H:%M:%SZ", Time::Stamp);
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
