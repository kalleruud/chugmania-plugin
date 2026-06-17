const string PluginName = Meta::ExecutingPlugin().Name;
const float AcceleratorThreshold = 0.01f;

class PlayerCaptureState
{
    CSmPlayer@ Player;
    int StartTime = -1;
    uint LastLandmarkIndex = uint(-1);
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
        state.LastLandmarkIndex = player.CurrentLaunchedRespawnLandmarkIndex;
        state.AcceleratorRecorded = false;
    }

    CaptureLandmarkEvent(playerIndex, player, data, state);

    if (data.StartTime >= 0 && !state.AcceleratorRecorded && data.InputGasPedal > AcceleratorThreshold) {
        state.AcceleratorRecorded = true;
        PrintEvent(
            "FIRST_ACCELERATOR",
            playerIndex,
            player,
            data,
            "gas=" + Text::Format("%.3f", data.InputGasPedal)
        );
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

    auto@ landmark = playground.Arena.MapLandmarks[landmarkIndex];
    if (landmark is null || landmark.Waypoint is null) return;

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
        " isFinish=" + landmark.Waypoint.IsFinish
    );
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
        " gas=" + Text::Format("%.3f", data.InputGasPedal) +
        " brake=" + data.InputIsBraking +
        " steer=" + Text::Format("%.3f", data.InputSteer) +
        " speed=" + Text::Format("%.3f", data.Speed) +
        " displaySpeed=" + data.DisplaySpeed +
        " position=" + FormatVec3(data.Position) +
        " velocity=" + FormatVec3(data.Velocity) +
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
}

int FindTerminalIndex(CSmArenaClient@ playground, CSmPlayer@ player)
{
    for (uint i = 0; i < playground.GameTerminals.Length; i++) {
        if (playground.GameTerminals[i].ControlledPlayer is player) return int(i);
    }
    return -1;
}

string FormatVec3(const vec3 &in value)
{
    return "(" +
        Text::Format("%.3f", value.x) + ", " +
        Text::Format("%.3f", value.y) + ", " +
        Text::Format("%.3f", value.z) + ")";
}

void OnDestroyed()
{
    print("[" + PluginName + "] Capture test unloaded.");
}
