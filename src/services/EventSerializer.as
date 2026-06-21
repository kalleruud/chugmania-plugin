Json::Value@ SerializePlayer(PlayerSnapshot@ player)
{
    Json::Value@ json = Json::Object();
    json["playerIndex"] = player.playerIndex;
    if (player.name.Length > 0) json["name"] = player.name;
    if (player.login.Length > 0) json["login"] = player.login;
    if (player.localId.Length > 0) json["localId"] = player.localId;
    if (player.accountId.Length > 0) json["accountId"] = player.accountId;
    return json;
}

Json::Value@ SerializeMap(MapSnapshot@ map)
{
    Json::Value@ json = Json::Object();
    json["name"] = map.name;
    json["isLaps"] = map.isLaps;
    if (map.uid.Length > 0) json["uid"] = map.uid;
    if (map.author.Length > 0) json["author"] = map.author;
    if (map.environment.Length > 0) json["environment"] = map.environment;
    if (map.mapType.Length > 0) json["type"] = map.mapType;
    if (map.isLaps && map.totalLaps > 0) json["totalLaps"] = map.totalLaps;
    json["checkpointsPerLap"] = map.checkpointsPerLap;
    Json::Value@ medals = Json::Object();
    if (map.authorTime > 0) medals["author"] = map.authorTime;
    if (map.goldTime > 0) medals["gold"] = map.goldTime;
    if (map.silverTime > 0) medals["silver"] = map.silverTime;
    if (map.bronzeTime > 0) medals["bronze"] = map.bronzeTime;
    if (medals.GetKeys().Length > 0) json["medalTimesMs"] = medals;
    return json;
}

Json::Value@ SerializeMode(ModeSnapshot@ mode)
{
    Json::Value@ json = Json::Object();
    json["name"] = mode.name;
    if (mode.modeType.Length > 0) json["type"] = mode.modeType;
    if (mode.settings !is null && mode.settings.GetKeys().Length > 0) json["settings"] = mode.settings;
    return json;
}

string SerializeEvent(CapturedEvent@ event)
{
    Json::Value@ json = Json::Object();
    json["schemaVersion"] = SCHEMA_VERSION;
    json["type"] = event.eventType;
    json["eventId"] = event.eventId;
    json["sequence"] = event.sequence;
    json["occurredAt"] = event.occurredAt;
    json["durationMs"] = event.durationMs;
    Json::Value@ game = Json::Object();
    game["gameId"] = event.gameId;
    game["totalPlayers"] = event.totalPlayers;
    json["game"] = game;
    Json::Value@ source = Json::Object();
    source["pluginName"] = PLUGIN_NAME;
    source["pluginVersion"] = Meta::ExecutingPlugin().Version;
    source["game"] = AdapterGameName();
    json["source"] = source;

    if (event.eventType == "start") {
        Json::Value@ players = Json::Array();
        for (uint i = 0; i < event.players.Length; i++) players.Add(SerializePlayer(event.players[i]));
        json["players"] = players;
        json["map"] = SerializeMap(event.map);
        json["mode"] = SerializeMode(event.mode);
    } else if (event.eventType == "end") {
        json["endReason"] = event.endReason;
    } else {
        json["player"] = SerializePlayer(event.player);
        if (event.eventType != "first_throttle") {
            Json::Value@ checkpoint = Json::Object();
            checkpoint["checkpointIndex"] = event.checkpointIndex;
            checkpoint["checkpointLapIndex"] = event.checkpointLapIndex;
            checkpoint["lapNumber"] = event.lapNumber;
            if (event.theoreticalDurationMs >= 0) checkpoint["theoreticalDurationMs"] = event.theoreticalDurationMs;
            if (event.lostMs >= 0) checkpoint["lostMs"] = event.lostMs;
            json["checkpoint"] = checkpoint;
        }
    }
    return Json::Write(json);
}
