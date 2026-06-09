void RenderPluginWindow()
{
    if (!Setting_ShowWindow) return;

    UI::SetNextWindowSize(480, 320, UI::Cond::FirstUseEver);
    if (UI::Begin(PluginName, Setting_ShowWindow)) {
        UI::Text("Plugin UI placeholder");

        // Window controls, tabs, tables, and user workflows go here.
    }
    UI::End();
}
