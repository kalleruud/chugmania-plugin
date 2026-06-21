void Main()
{
    UtcClockService::Initialize();
#if TURBO
    print("[" + PluginInfo::Name + "] Turbo race webhook capture loaded with native timing.");
#else
    print("[" + PluginInfo::Name + "] Race webhook capture loaded with MLFeed game timing.");
#endif
}

void Update(float dt)
{
    RaceCaptureService::Update();
}

void OnDestroyed()
{
    print("[" + PluginInfo::Name + "] Race webhook capture unloaded.");
}
