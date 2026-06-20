namespace WebhookService
{
    array<WebhookJob@> Queue;
    bool Delivering = false;

    void Enqueue(const string &in eventId, const string &in body)
    {
        WebhookJob@ job = WebhookJob();
        job.EventId = eventId;
        job.Body = body;
        Queue.InsertLast(job);
    }

    void StartDelivery()
    {
        if (Delivering || Queue.Length == 0) return;
        Delivering = true;
        startnew(DeliverQueued);
    }

    void DeliverQueued()
    {
        while (Queue.Length > 0) Deliver(Queue[0]);
        Delivering = false;
    }

    void Deliver(WebhookJob@ job)
    {
        uint maxAttempts = Setting_WebhookRetryCount + 1;
        for (uint attemptNumber = 1; attemptNumber <= maxAttempts; attemptNumber++) {
            auto request = Net::HttpRequest();
            request.Method = Net::HttpMethod::Post;
            request.Url = Setting_WebhookEndpoint;
            request.Headers["Content-Type"] = "application/json";
            if (Setting_WebhookApiKey.Length > 0) {
                request.Headers["X-API-Key"] = Setting_WebhookApiKey;
            }
            request.Body = job.Body;
            request.Start();
            while (!request.Finished()) yield();

            int status = request.ResponseCode();
            if (status >= 200 && status < 300) {
                print("[" + PluginInfo::Name + "] WEBHOOK_DELIVERED id=" +
                    job.EventId + " status=" + status);
                Queue.RemoveAt(0);
                return;
            }

            warn("[" + PluginInfo::Name + "] WEBHOOK_FAILED id=" + job.EventId +
                " attempt=" + attemptNumber + " status=" + status);
            if (attemptNumber < maxAttempts) sleep(RetryDelayMs(attemptNumber));
        }

        error("[" + PluginInfo::Name + "] WEBHOOK_DROPPED id=" + job.EventId +
            " after=" + maxAttempts + " attempts");
        Queue.RemoveAt(0);
    }

    uint RetryDelayMs(uint attemptNumber)
    {
        if (attemptNumber == 1) return 1000;
        if (attemptNumber == 2) return 3000;
        return 10000;
    }
}
