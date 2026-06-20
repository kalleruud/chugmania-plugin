class RaceEventCapture
{
    uint CaptureOrder;
    string Type;
    string AtUtc;
    int DurationMs;
    int CheckpointIndex = -1;
    int TheoreticalDurationMs = -1;
}

class PlayerCaptureState
{
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
    int LastRaceTimeMs = 0;
    bool IsLocalPlayer = false;
    int TheoreticalRaceTimeMs = -1;
    int RaceRank = -1;
    int RaceRespawnRank = -1;
    int TimeAttackRank = -1;
    int CapturedRespawnEvents = 0;
    float LatencyEstimateMs = 0.0f;
    float LatencySampleCount = 0.0f;
    array<uint> BestRaceTimes;
    array<uint> BestLapTimes;
    bool AcceleratorRecorded = false;
    bool Finished = false;
    int FinishPosition = -1;
    array<RaceEventCapture@> Events;
}

class MapCaptureState
{
    string Uid;
    string Name;
    string AuthorLogin;
    string AuthorName;
    string MapType;
    string MapStyle;
    bool IsLapRace = false;
    int AuthorTimeMs = 0;
    int GoldTimeMs = 0;
    int SilverTimeMs = 0;
    int BronzeTimeMs = 0;
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
    string ModeName;
    int ModeStartTime = -1;
    int ModeEndTime = -1;
    int ModeTimeLimitMs = -1;
    int LapCountOverride = -1;
    int PointsLimit = -1;
    int SpawnDelayDurationMs = -1;
    string RespawnBehavior;
    string CheckpointBehavior;
    string GiveUpBehavior;
    bool GiveUpRespawnAfter = false;
    bool GiveUpSkipAfterFinish = false;
    bool UsesTeams = false;
    bool WarmupActive = false;
}

class WebhookJob
{
    string EventId;
    string Body;
}

class CompletedRaceAttempt
{
    RaceAttemptState@ Attempt;
    MapCaptureState@ Map;
    array<PlayerCaptureState@> Players;
    string EndReason;
    string EndedAtUtc;
    int DurationMs;
}
