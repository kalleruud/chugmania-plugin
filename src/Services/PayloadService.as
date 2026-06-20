namespace PayloadService
{
    Json::Value@ Build(CompletedRaceAttempt@ completed)
    {
        Json::Value@ root = Json::Object();
        root["schemaVersion"] = "1.2";
        root["eventType"] = "race.attempt.ended";
        root["eventId"] = completed.Attempt.AttemptId;
        root["occurredAtUtc"] = completed.EndedAtUtc;
        root["source"] = BuildSource();
        root["attempt"] = BuildAttempt(completed);
        return root;
    }

    Json::Value@ BuildSource()
    {
        Json::Value@ source = Json::Object();
        source["pluginName"] = PluginInfo::Name;
        source["pluginVersion"] = PluginInfo::Version;
#if TURBO
        source["game"] = "Trackmania Turbo";
#else
        source["game"] = "Trackmania";
#endif
        return source;
    }

    Json::Value@ BuildAttempt(CompletedRaceAttempt@ completed)
    {
        RaceAttemptState@ state = completed.Attempt;
        Json::Value@ json = Json::Object();
        json["attemptId"] = state.AttemptId;
        json["format"] = completed.Players.Length > 1 ? "split_screen" : "solo";
        json["playerCount"] = completed.Players.Length;
        json["startedAtUtc"] = UtcClockService::Format(state.StartedAtUtcMs);
        json["endedAtUtc"] = completed.EndedAtUtc;
        json["durationMs"] = completed.DurationMs;
        json["endReason"] = completed.EndReason;
#if TURBO
        json["timingSource"] = "turbo_native_race_clock";
#else
        json["timingSource"] = "mlfeed_game_clock";
#endif
        json["mode"] = BuildMode(state);
        json["map"] = BuildMap(state, completed.Map);
        json["players"] = BuildPlayers(completed.Players);
        return json;
    }

    Json::Value@ BuildMode(RaceAttemptState@ state)
    {
        Json::Value@ json = Json::Object();
        if (state.ModeName.Length > 0) json["name"] = state.ModeName;
        else json["name"] = Json::Parse("null");
        json["warmupActive"] = state.WarmupActive;
        SetNullableInt(json, "startTime", state.ModeStartTime);
        SetNullableInt(json, "endTime", state.ModeEndTime);
        SetNullableInt(json, "timeLimitMs", state.ModeTimeLimitMs);

        Json::Value@ settings = Json::Object();
        SetNullableInt(settings, "lapCountOverride", state.LapCountOverride);
        SetNullableInt(settings, "pointsLimit", state.PointsLimit);
        SetNullableInt(settings, "spawnDelayDurationMs", state.SpawnDelayDurationMs);
#if TURBO
        settings["respawnBehavior"] = Json::Parse("null");
        settings["checkpointBehavior"] = Json::Parse("null");
        settings["giveUpBehavior"] = Json::Parse("null");
        settings["giveUpRespawnAfter"] = Json::Parse("null");
        settings["giveUpSkipAfterFinish"] = Json::Parse("null");
        settings["usesTeams"] = Json::Parse("null");
#else
        settings["respawnBehavior"] = state.RespawnBehavior;
        settings["checkpointBehavior"] = state.CheckpointBehavior;
        settings["giveUpBehavior"] = state.GiveUpBehavior;
        settings["giveUpRespawnAfter"] = state.GiveUpRespawnAfter;
        settings["giveUpSkipAfterFinish"] = state.GiveUpSkipAfterFinish;
        settings["usesTeams"] = state.UsesTeams;
#endif
        json["settings"] = settings;
        return json;
    }

    Json::Value@ BuildMap(RaceAttemptState@ state, MapCaptureState@ map)
    {
        Json::Value@ json = Json::Object();
        json["uid"] = map.Uid;
        json["name"] = map.Name;
        json["authorLogin"] = map.AuthorLogin;
        json["authorName"] = map.AuthorName;
        json["mapType"] = map.MapType;
        json["mapStyle"] = map.MapStyle;
#if TURBO
        SetNullableInt(json, "laps", map.Laps);
#else
        SetNullableInt(json, "laps", state.MlFeedLapCount);
#endif
        json["isLapRace"] = map.IsLapRace;
        SetNullableInt(json, "checkpointsPerLap", state.CheckpointsPerLap);
        SetNullableInt(json, "waypointsToFinish", state.WaypointsToFinish);
        SetNullableInt(json, "mlFeedLapCount", state.MlFeedLapCount);
        json["medalTimesMs"] = BuildMedalTimes(map);
        return json;
    }

    Json::Value@ BuildMedalTimes(MapCaptureState@ map)
    {
        Json::Value@ medals = Json::Object();
        medals["author"] = map.AuthorTimeMs;
        medals["gold"] = map.GoldTimeMs;
        medals["silver"] = map.SilverTimeMs;
        medals["bronze"] = map.BronzeTimeMs;
        return medals;
    }

    Json::Value@ BuildPlayers(const array<PlayerCaptureState@>@ players)
    {
        Json::Value@ json = Json::Array();
        for (uint i = 0; i < players.Length; i++) json.Add(BuildPlayer(players[i]));
        return json;
    }

    Json::Value@ BuildPlayer(PlayerCaptureState@ state)
    {
        Json::Value@ json = Json::Object();
        AddIdentity(json, state);
        json["events"] = BuildEvents(state.Events);
        return json;
    }

    void AddIdentity(Json::Value@ json, PlayerCaptureState@ state)
    {
        json["participantKey"] = state.ParticipantKey;
        json["playerIndex"] = state.PlayerIndex;
        json["terminalIndex"] = state.TerminalIndex;
        json["login"] = state.Login;
        if (state.AccountId.Length > 0) json["accountId"] = state.AccountId;
        else json["accountId"] = Json::Parse("null");
        json["name"] = state.Name;
        SetNullableInt(json, "finishPosition", state.FinishPosition);
    }

    Json::Value@ BuildEvents(const array<RaceEventCapture@>@ events)
    {
        Json::Value@ json = Json::Array();
        array<RaceEventCapture@> ordered = OrderedEvents(events);
        for (uint i = 0; i < ordered.Length; i++) json.Add(BuildEvent(ordered[i]));
        return json;
    }

    Json::Value@ BuildEvent(RaceEventCapture@ event)
    {
        Json::Value@ json = Json::Object();
        json["type"] = event.Type;
        json["atUtc"] = event.AtUtc;
        json["durationMs"] = event.DurationMs;
        if (event.Type == "checkpoint" || event.Type == "finish") {
            Json::Value@ checkpoint = Json::Object();
            checkpoint["index"] = event.CheckpointIndex;
            json["checkpoint"] = checkpoint;
            SetNullableInt(json, "theoreticalDurationMs", event.TheoreticalDurationMs);
        } else if (event.Type == "respawn") {
            Json::Value@ respawn = Json::Object();
            SetNullableInt(respawn, "checkpointIndex", event.CheckpointIndex);
            json["respawn"] = respawn;
        }
        return json;
    }

    void SetNullableInt(Json::Value@ object, const string &in key, int value)
    {
        if (value >= 0) object[key] = value;
        else object[key] = Json::Parse("null");
    }

    array<RaceEventCapture@> OrderedEvents(const array<RaceEventCapture@>@ events)
    {
        array<RaceEventCapture@> ordered;
        for (uint i = 0; i < events.Length; i++) ordered.InsertLast(events[i]);
        for (uint i = 1; i < ordered.Length; i++) InsertEvent(ordered, i);
        return ordered;
    }

    void InsertEvent(array<RaceEventCapture@>@ ordered, uint index)
    {
        RaceEventCapture@ candidate = ordered[index];
        int position = int(index) - 1;
        while (position >= 0 && ComesBefore(candidate, ordered[position])) {
            @ordered[position + 1] = ordered[position];
            position--;
        }
        @ordered[position + 1] = candidate;
    }

    bool ComesBefore(RaceEventCapture@ left, RaceEventCapture@ right)
    {
        if (left.DurationMs != right.DurationMs) return left.DurationMs < right.DurationMs;
        int leftPriority = EventPriority(left.Type);
        int rightPriority = EventPriority(right.Type);
        if (leftPriority != rightPriority) return leftPriority < rightPriority;
        return left.CaptureOrder < right.CaptureOrder;
    }

    int EventPriority(const string &in type)
    {
        if (type == "start") return 0;
        if (type == "first_throttle") return 1;
        if (type == "checkpoint") return 2;
        if (type == "respawn") return 3;
        return 4;
    }

}
