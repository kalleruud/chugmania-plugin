const string PluginName = Meta::ExecutingPlugin().Name;

void Main()
{
    // Long-running startup or background coroutine code goes here.
    // Use yield() or sleep(ms) in loops so the game stays responsive.
}

void RenderMenu()
{
    // Add compact Openplanet menu entries here.
}

void RenderMenuMain()
{
    // Add main menu bar entries or nested menus here.
}

void RenderInterface()
{
    // Render the plugin's primary UI here.
    RenderPluginWindow();
}

void Update(float dt)
{
    // Per-frame non-UI logic goes here.
}

void OnDestroyed()
{
    // Cleanup code goes here.
}
