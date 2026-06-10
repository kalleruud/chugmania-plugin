const string PluginName = Meta::ExecutingPlugin().Name;
const float AcceleratorThreshold = 0.01f;

class PlayerCaptureState
{
    CSmPlayer@ Player;
    int StartTime = -1;
    int EndTime = -1;
    int LapStartTime = -1;
    uint CurrentLapNumber = 0;
    uint LapWaypointCount = 0;
    uint RaceWaypointCount = 0;
    uint LastLandmarkIndex = uint(-1);
    int LastLapCheckpointTime = 0;
    int LastRaceCheckpointTime = 0;
    bool AcceleratorRecorded = false;
}

array<PlayerCaptureState@> PlayerStates;
CGameCtnChallenge@ CurrentMap;
bool PlaygroundWasAvailable = false;

void Main()
{
    print("[" + PluginName + "] Capture test loaded. Start a local race to record data.");
}

void Update(float dt)
{
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    if (app is null) return;

    CSmArenaClient@ playground = cast<CSmArenaClient>(app.CurrentPlayground);
    if (playground is null) {
        if (PlaygroundWasAvailable) {
            print("[" + PluginName + "] Playground closed; capture state cleared.");
            PlayerStates.RemoveRange(0, PlayerStates.Length);
            @CurrentMap = null;
            PlaygroundWasAvailable = false;
        }
        return;
    }

    PlaygroundWasAvailable = true;
    if (CurrentMap !is playground.Map) {
        @CurrentMap = playground.Map;
        PlayerStates.RemoveRange(0, PlayerStates.Length);
        PrintMapInfo(playground);
    }

    for (uint i = 0; i < playground.Players.Length; i++) {
        CSmPlayer@ player = cast<CSmPlayer>(playground.Players[i]);
        if (player is null || player.ScriptAPI is null) continue;

        CSmScriptPlayer@ data = cast<CSmScriptPlayer>(player.ScriptAPI);
        if (data is null) continue;

        PlayerCaptureState@ state = FindPlayerState(player);
        if (state is null) {
            @state = CreatePlayerState(player, data);
            PlayerStates.InsertLast(state);
            PrintEvent("PLAYER_FOUND", i, player, data, "terminal=" + FindTerminalIndex(playground, player));
            continue;
        }

        CapturePlayerEvents(i, player, data, state);
    }
}

PlayerCaptureState@ FindPlayerState(CSmPlayer@ player)
{
    for (uint i = 0; i < PlayerStates.Length; i++) {
        if (PlayerStates[i].Player is player) return PlayerStates[i];
    }
    return null;
}

PlayerCaptureState@ CreatePlayerState(CSmPlayer@ player, CSmScriptPlayer@ data)
{
    PlayerCaptureState@ state = PlayerCaptureState();
    @state.Player = player;
    state.StartTime = data.StartTime;
    state.EndTime = data.EndTime;
    state.LapStartTime = data.LapStartTime;
    state.CurrentLapNumber = data.CurrentLapNumber;
    state.LapWaypointCount = data.CurrentLapWaypointTimes.Length;
    state.RaceWaypointCount = data.RaceWaypointTimes.Length;
    state.LastLandmarkIndex = player.CurrentLaunchedRespawnLandmarkIndex;
    return state;
}

void CapturePlayerEvents(
    uint playerIndex,
    CSmPlayer@ player,
    CSmScriptPlayer@ data,
    PlayerCaptureState@ state
)
{
    if (data.StartTime != state.StartTime) {
        state.StartTime = data.StartTime;
        state.EndTime = data.EndTime;
        state.LapStartTime = data.LapStartTime;
        state.CurrentLapNumber = data.CurrentLapNumber;
        state.LapWaypointCount = 0;
        state.RaceWaypointCount = 0;
        state.LastLandmarkIndex = player.CurrentLaunchedRespawnLandmarkIndex;
        state.LastLapCheckpointTime = 0;
        state.LastRaceCheckpointTime = 0;
        state.AcceleratorRecorded = false;
        PrintEvent("RACE_START", playerIndex, player, data, "startTime=" + data.StartTime);
    }

    CaptureLandmarkEvent(playerIndex, player, data, state);

    if (data.CurrentLapNumber != state.CurrentLapNumber) {
        int lapTime = LastValue(data.PreviousLapWaypointTimes);
        PrintEvent(
            "LAP_NUMBER_CHANGED",
            playerIndex,
            player,
            data,
            "previousLap=" + state.CurrentLapNumber +
            " currentLap=" + data.CurrentLapNumber +
            " previousLapFinalWaypointMs=" + lapTime
        );
        state.CurrentLapNumber = data.CurrentLapNumber;
        state.LapWaypointCount = 0;
        state.LastLapCheckpointTime = 0;
        state.AcceleratorRecorded = false;
    }

    if (data.LapStartTime != state.LapStartTime) {
        state.LapStartTime = data.LapStartTime;
        state.LapWaypointCount = 0;
        state.LastLapCheckpointTime = 0;
        state.AcceleratorRecorded = false;
        PrintEvent(
            "LAP_START",
            playerIndex,
            player,
            data,
            "lap=" + data.CurrentLapNumber + " lapStartTime=" + data.LapStartTime
        );
    }

    if (!state.AcceleratorRecorded && data.CurrentLapTime >= 0 && data.InputGasPedal > AcceleratorThreshold) {
        state.AcceleratorRecorded = true;
        PrintEvent(
            "FIRST_ACCELERATOR",
            playerIndex,
            player,
            data,
            "lap=" + data.CurrentLapNumber +
            " delayMs=" + data.CurrentLapTime +
            " delay=" + FormatTime(data.CurrentLapTime) +
            " gas=" + Text::Format("%.3f", data.InputGasPedal)
        );
    }

    if (data.CurrentLapWaypointTimes.Length < state.LapWaypointCount) {
        state.LapWaypointCount = data.CurrentLapWaypointTimes.Length;
    }
    while (state.LapWaypointCount < data.CurrentLapWaypointTimes.Length) {
        uint waypointIndex = state.LapWaypointCount;
        int waypointTime = int(data.CurrentLapWaypointTimes[waypointIndex]);
        int previousTime = waypointIndex == 0
            ? 0
            : int(data.CurrentLapWaypointTimes[waypointIndex - 1]);
        PrintEvent(
            "LAP_WAYPOINT",
            playerIndex,
            player,
            data,
            "lap=" + data.CurrentLapNumber +
            " waypoint=" + waypointIndex +
            " timeMs=" + waypointTime +
            " time=" + FormatTime(waypointTime) +
            " sectorMs=" + (waypointTime - previousTime)
        );
        state.LapWaypointCount++;
    }

    if (data.RaceWaypointTimes.Length < state.RaceWaypointCount) {
        state.RaceWaypointCount = data.RaceWaypointTimes.Length;
    }
    while (state.RaceWaypointCount < data.RaceWaypointTimes.Length) {
        uint waypointIndex = state.RaceWaypointCount;
        int waypointTime = int(data.RaceWaypointTimes[waypointIndex]);
        PrintEvent(
            "RACE_WAYPOINT",
            playerIndex,
            player,
            data,
            "waypoint=" + waypointIndex +
            " timeMs=" + waypointTime +
            " time=" + FormatTime(waypointTime)
        );
        state.RaceWaypointCount++;
    }

    if (data.EndTime != state.EndTime) {
        state.EndTime = data.EndTime;
        if (data.EndTime >= 0) {
            int raceTime = LastValue(data.RaceWaypointTimes);
            if (raceTime < 0) raceTime = data.CurrentRaceTime;
            PrintEvent(
                "RACE_END_TIME_CHANGED",
                playerIndex,
                player,
                data,
                "raceTimeMs=" + raceTime + " raceTime=" + FormatTime(raceTime)
            );
        }
    }
}

void CaptureLandmarkEvent(
    uint playerIndex,
    CSmPlayer@ player,
    CSmScriptPlayer@ data,
    PlayerCaptureState@ state
)
{
    uint landmarkIndex = player.CurrentLaunchedRespawnLandmarkIndex;
    if (landmarkIndex == state.LastLandmarkIndex) return;

    state.LastLandmarkIndex = landmarkIndex;
    if (landmarkIndex == uint(-1)) return;

    CSmArenaClient@ playground = cast<CSmArenaClient>(GetApp().CurrentPlayground);
    if (playground is null || playground.Arena is null) return;
    if (landmarkIndex >= playground.Arena.MapLandmarks.Length) return;

    CSmScriptMapLandmark@ landmark = playground.Arena.MapLandmarks[landmarkIndex];
    if (landmark is null || landmark.Waypoint is null) return;

    int lapTime = data.CurrentLapTime;
    int raceTime = data.CurrentRaceTime;
    int lapSectorTime = lapTime - state.LastLapCheckpointTime;
    int raceSectorTime = raceTime - state.LastRaceCheckpointTime;

    string eventName = "CHECKPOINT";
    if (landmark.Waypoint.IsMultiLap) eventName = "LAP_FINISH";
    if (landmark.Waypoint.IsFinish) eventName = "RACE_FINISH";

    PrintEvent(
        eventName,
        playerIndex,
        player,
        data,
        "landmarkIndex=" + landmarkIndex +
        " order=" + landmark.Order +
        " tag=\"" + landmark.Tag + "\"" +
        " isMultiLap=" + landmark.Waypoint.IsMultiLap +
        " isFinish=" + landmark.Waypoint.IsFinish +
        " lapTimeMs=" + lapTime +
        " raceTimeMs=" + raceTime +
        " lapSectorMs=" + lapSectorTime +
        " raceSectorMs=" + raceSectorTime
    );

    state.LastLapCheckpointTime = landmark.Waypoint.IsMultiLap ? 0 : lapTime;
    state.LastRaceCheckpointTime = raceTime;
}

void PrintMapInfo(CSmArenaClient@ playground)
{
    if (playground.Map is null) return;

    CGameCtnChallenge@ map = playground.Map;
    print(
        "[" + PluginName + "] MAP" +
        " name=\"" + Text::StripFormatCodes(map.MapName) + "\"" +
        " authorLogin=\"" + map.AuthorLogin + "\"" +
        " authorName=\"" + Text::StripFormatCodes(map.AuthorNickName) + "\"" +
        " type=\"" + Text::StripFormatCodes(map.MapType) + "\"" +
        " style=\"" + Text::StripFormatCodes(map.MapStyle) + "\"" +
        " laps=" + map.TMObjective_NbLaps +
        " isLapRace=" + map.TMObjective_IsLapRace +
        " authorTimeMs=" + map.TMObjective_AuthorTime +
        " goldTimeMs=" + map.TMObjective_GoldTime +
        " silverTimeMs=" + map.TMObjective_SilverTime +
        " bronzeTimeMs=" + map.TMObjective_BronzeTime +
        " players=" + playground.Players.Length +
        " terminals=" + playground.GameTerminals.Length
    );
}

void PrintEvent(
    const string &in eventName,
    uint playerIndex,
    CSmPlayer@ player,
    CSmScriptPlayer@ data,
    const string &in eventData
)
{
    string login = data.Login;
    string name = Text::StripFormatCodes(data.Name);
    if (login.Length == 0 && player.User !is null) login = player.User.Login;
    if (name.Length == 0 && player.User !is null) name = Text::StripFormatCodes(player.User.Name);

    print(
        "[" + PluginName + "] " + eventName +
        " playerIndex=" + playerIndex +
        " login=\"" + login + "\"" +
        " name=\"" + name + "\" " +
        eventData
    );
    PrintPlayerSnapshot(playerIndex, player, data);
}

void PrintPlayerSnapshot(uint playerIndex, CSmPlayer@ player, CSmScriptPlayer@ data)
{
    print(
        "[" + PluginName + "] SNAPSHOT" +
        " playerIndex=" + playerIndex +
        " startTime=" + data.StartTime +
        " endTime=" + data.EndTime +
        " lapStartTime=" + data.LapStartTime +
        " currentLap=" + data.CurrentLapNumber +
        " currentLapTimeMs=" + data.CurrentLapTime +
        " currentRaceTimeMs=" + data.CurrentRaceTime +
        " lapRespawns=" + data.CurrentLapRespawns +
        " raceRespawns=" + data.CurrentRaceRespawns +
        " lapWaypoints=" + data.CurrentLapWaypointTimes.Length +
        " raceWaypoints=" + data.RaceWaypointTimes.Length +
        " gas=" + Text::Format("%.3f", data.InputGasPedal) +
        " brake=" + data.InputIsBraking +
        " steer=" + Text::Format("%.3f", data.InputSteer) +
        " speed=" + Text::Format("%.3f", data.Speed) +
        " displaySpeed=" + data.DisplaySpeed +
        " position=" + data.Position +
        " velocity=" + data.Velocity +
        " rpm=" + Text::Format("%.3f", data.EngineRpm) +
        " gear=" + data.EngineCurGear +
        " turbo=" + Text::Format("%.3f", data.EngineTurboRatio) +
        " wheelsContact=" + data.WheelsContactCount +
        " wheelsSkidding=" + data.WheelsSkiddingCount +
        " flyingDurationMs=" + data.FlyingDuration +
        " skiddingDurationMs=" + data.SkiddingDuration +
        " spawnIndex=" + player.SpawnIndex +
        " isFake=" + data.IsFakePlayer +
        " isBot=" + data.IsBot
    );

    PrintTimes("currentLapWaypointTimes", playerIndex, data.CurrentLapWaypointTimes);
    PrintTimes("previousLapWaypointTimes", playerIndex, data.PreviousLapWaypointTimes);
    PrintTimes("lapWaypointTimes", playerIndex, data.LapWaypointTimes);
    PrintTimes("raceWaypointTimes", playerIndex, data.RaceWaypointTimes);
}

void PrintTimes(const string &in label, uint playerIndex, const MwFastBuffer<uint> &in times)
{
    string value = "[";
    for (uint i = 0; i < times.Length; i++) {
        if (i > 0) value += ",";
        value += times[i];
    }
    value += "]";
    print("[" + PluginName + "] TIMES playerIndex=" + playerIndex + " " + label + "=" + value);
}

int LastValue(const MwFastBuffer<uint> &in values)
{
    if (values.Length == 0) return -1;
    return int(values[values.Length - 1]);
}

int FindTerminalIndex(CSmArenaClient@ playground, CSmPlayer@ player)
{
    for (uint i = 0; i < playground.GameTerminals.Length; i++) {
        if (playground.GameTerminals[i].ControlledPlayer is player) return int(i);
    }
    return -1;
}

string FormatTime(int milliseconds)
{
    if (milliseconds < 0) return "n/a";

    int minutes = milliseconds / 60000;
    int seconds = (milliseconds / 1000) % 60;
    int millis = milliseconds % 1000;
    return Text::Format("%d:%02d.%03d", minutes, seconds, millis);
}

void OnDestroyed()
{
    print("[" + PluginName + "] Capture test unloaded.");
}
