namespace PluginInfo
{
    const string Name = Meta::ExecutingPlugin().Name;
    const string Version = Meta::ExecutingPlugin().Version;
}

[Setting category="Webhook" name="Enabled" description="Send one webhook when a local race attempt ends."]
bool Setting_WebhookEnabled = false;

[Setting category="Webhook" name="Endpoint" description="HTTPS endpoint that receives race.attempt.ended JSON payloads."]
string Setting_WebhookEndpoint = "";

[Setting category="Webhook" name="API key" description="Sent in the X-API-Key request header." password=true]
string Setting_WebhookApiKey = "";

[Setting category="Webhook" name="Retry count" description="Number of retries after the initial request." min=0 max=5]
uint Setting_WebhookRetryCount = 3;
