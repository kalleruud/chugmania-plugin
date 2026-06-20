void Main()
{
    UtcClockService::Initialize();
    print("[" + PluginInfo::Name + "] Race webhook capture loaded with MLFeed game timing.");
}

void Update(float dt)
{
    RaceCaptureService::Update();
}

void OnDestroyed()
{
    print("[" + PluginInfo::Name + "] Race webhook capture unloaded.");
}
