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
                print("[" + PluginInfo::Name + "] WEBHOOK_CONSUMED id=" +
                    job.EventId + " status=" + status);
                Queue.RemoveAt(0);
                return;
            }

            if (status == 503) {
                if (attemptNumber < maxAttempts) {
                    uint retryDelayMs = RetryDelayMs(request, status, attemptNumber);
                    warn("[" + PluginInfo::Name + "] WEBHOOK_NOT_CONSUMED id=" +
                        job.EventId + " attempt=" + attemptNumber + " status=" +
                        status + " retryInMs=" + retryDelayMs);
                    sleep(retryDelayMs);
                } else {
                    warn("[" + PluginInfo::Name + "] WEBHOOK_NOT_CONSUMED id=" +
                        job.EventId + " attempt=" + attemptNumber + " status=" +
                        status);
                }
                continue;
            }

            if (attemptNumber < maxAttempts) {
                uint retryDelayMs = RetryDelayMs(request, status, attemptNumber);
                warn("[" + PluginInfo::Name + "] WEBHOOK_FAILED id=" + job.EventId +
                    " attempt=" + attemptNumber + " status=" + status +
                    " retryInMs=" + retryDelayMs);
                sleep(retryDelayMs);
            } else {
                warn("[" + PluginInfo::Name + "] WEBHOOK_FAILED id=" + job.EventId +
                    " attempt=" + attemptNumber + " status=" + status);
            }
        }

        error("[" + PluginInfo::Name + "] WEBHOOK_DROPPED id=" + job.EventId +
            " after=" + maxAttempts + " attempts");
        Queue.RemoveAt(0);
    }

    uint RetryDelayMs(
        Net::HttpRequest@ request,
        int status,
        uint attemptNumber
    )
    {
        if (status == 429 || status == 503) return RateLimitDelayMs(request, attemptNumber);
        if (attemptNumber == 1) return 1000;
        if (attemptNumber == 2) return 3000;
        return 10000;
    }

    uint RateLimitDelayMs(Net::HttpRequest@ request, uint attemptNumber)
    {
        int64 resetAt = 0;
        string rateLimitReset = request.ResponseHeader("X-RateLimit-Reset");
        if (Text::TryParseInt64(rateLimitReset, resetAt) && resetAt > Time::Stamp) {
            return ClampedDelayMs(int(resetAt - Time::Stamp));
        }

        if (attemptNumber == 1) return 30000;
        if (attemptNumber == 2) return 60000;
        return 120000;
    }

    uint ClampedDelayMs(int seconds)
    {
        return uint(Math::Clamp(seconds, 1, 300)) * 1000;
    }
}
