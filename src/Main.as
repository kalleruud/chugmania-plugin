void Main()
{
    UtcClockService::Initialize();
    print("[" + PluginInfo::Name + "] Race webhook capture loaded with MLFeed game timing.");

    while (true) {
        WebhookService::DeliverNextIfQueued();
        yield();
    }
}

void Update(float dt)
{
    RaceCaptureService::Update();
}

void OnDestroyed()
{
    print("[" + PluginInfo::Name + "] Race webhook capture unloaded.");
}
