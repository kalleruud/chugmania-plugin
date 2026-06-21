[Setting name="Endpoint URL" description="Webhook destination. Capture is disabled while empty." category="Webhook"]
string Setting_EndpointUrl = "";

[Setting name="Authentication token" description="Bearer token. The value is never logged." category="Webhook" password]
string Setting_AuthenticationToken = "";

[Setting name="Maximum retry count" description="Retries after the initial request." category="Webhook" min=0 max=10]
uint Setting_MaximumRetryCount = 3;

RoundTracker@ g_tracker;
GameAdapter@ g_adapter;
WebhookDelivery@ g_delivery;

void Main()
{
    @g_delivery = WebhookDelivery();
    @g_tracker = RoundTracker(g_delivery);
    @g_adapter = CreateGameAdapter();
    startnew(CoroutineFunc(DeliveryLoop));
}

void DeliveryLoop() { g_delivery.Run(); }

void Update(float dt)
{
    if (g_adapter is null || g_tracker is null) return;
    g_tracker.Update(g_adapter.Observe());
}

void OnDestroyed()
{
    if (g_tracker !is null) g_tracker.Stop("unknown");
}
