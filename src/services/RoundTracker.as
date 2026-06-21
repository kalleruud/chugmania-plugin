class TrackedPlayer
{
    bool throttled;
    bool finished;
    uint checkpointIndex;
    uint respawnCount;
}

class RoundTracker
{
    WebhookDelivery@ delivery;
    bool running;
    string gameId;
    string sessionKey;
    uint sequence;
    uint lastDurationMs;
    array<PlayerSnapshot@> roster;
    array<TrackedPlayer@> tracked;

    RoundTracker(WebhookDelivery@ sender) { @delivery = sender; }

    void Update(GameObservation@ observation)
    {
        if (observation is null || !observation.local || !CaptureEnabled()) {
            if (running && (observation is null || !observation.active)) Stop("aborted");
            return;
        }
        if (!observation.active) {
            if (running) Stop(observation.endReason);
            return;
        }
        if (!running || observation.sessionKey != sessionKey) {
            if (running) Stop("restarted");
            Start(observation);
        }
        CapturePlayers(observation.playerStates);
    }

    void Start(GameObservation@ observation)
    {
        running = true;
        gameId = CreateUuidV4();
        sessionKey = observation.sessionKey;
        sequence = 0;
        lastDurationMs = 0;
        roster = observation.players;
        tracked.Resize(roster.Length);
        for (uint i = 0; i < tracked.Length; i++) @tracked[i] = TrackedPlayer();
        CapturedEvent@ event = NewEvent("start", 0);
        event.players = roster;
        @event.map = observation.map;
        @event.mode = observation.mode;
        Enqueue(event);
    }

    void CapturePlayers(array<PlayerObservation@>@ states)
    {
        for (uint i = 0; i < states.Length; i++) {
            PlayerObservation@ state = states[i];
            if (state is null || state.player is null || state.player.playerIndex >= tracked.Length) continue;
            uint index = state.player.playerIndex;
            lastDurationMs = Math::Max(lastDurationMs, state.durationMs);
            TrackedPlayer@ previous = tracked[index];
            if (!previous.throttled && state.throttle > 0) {
                previous.throttled = true;
                EmitPlayerEvent("first_throttle", state);
            }
            if (state.checkpointIndex > previous.checkpointIndex) {
                string type = state.finished ? "finish" : (state.checkpointLapIndex == 0 ? "lap" : "checkpoint");
                previous.checkpointIndex = state.checkpointIndex;
                if (!previous.finished) EmitPlayerEvent(type, state);
            }
            while (previous.respawnCount < state.respawnCount) {
                previous.respawnCount++;
                EmitPlayerEvent("respawn", state);
            }
            previous.finished = previous.finished || state.finished;
        }
    }

    void EmitPlayerEvent(const string &in type, PlayerObservation@ state)
    {
        CapturedEvent@ event = NewEvent(type, state.durationMs);
        @event.player = roster[state.player.playerIndex];
        event.checkpointIndex = state.checkpointIndex;
        event.checkpointLapIndex = state.checkpointLapIndex;
        event.lapNumber = state.lapNumber;
        event.theoreticalDurationMs = state.theoreticalDurationMs;
        event.lostMs = state.lostMs;
        Enqueue(event);
    }

    void Stop(const string &in reason)
    {
        if (!running) return;
        CapturedEvent@ event = NewEvent("end", lastDurationMs);
        event.endReason = NormalizeEndReason(reason);
        Enqueue(event);
        running = false;
        roster.Resize(0);
        tracked.Resize(0);
    }

    CapturedEvent@ NewEvent(const string &in type, uint durationMs)
    {
        CapturedEvent@ event = CapturedEvent();
        event.eventType = type;
        event.eventId = CreateUuidV4();
        event.gameId = gameId;
        event.sequence = sequence++;
        event.occurredAt = OccurredAtUtc();
        event.durationMs = durationMs;
        event.totalPlayers = roster.Length;
        return event;
    }

    void Enqueue(CapturedEvent@ event)
    {
        print("[emit] " + event.sequence + " " + event.eventType + " " + event.durationMs + "ms");
        delivery.Enqueue(event.eventId, event.eventType, SerializeEvent(event));
    }

}

bool CaptureEnabled() { return Setting_EndpointUrl.Length > 0; }

string NormalizeEndReason(const string &in reason)
{
    if (reason == "completed" || reason == "restarted" || reason == "aborted") return reason;
    return "unknown";
}
