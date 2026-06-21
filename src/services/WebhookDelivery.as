class WebhookDelivery
{
    array<PendingWebhook@> queue;
    bool stopping;

    void Enqueue(const string &in eventId, const string &in payload)
    {
        if (queue.Length >= MAX_QUEUE_SIZE) {
            error("Webhook queue full; dropped event " + eventId);
            return;
        }
        queue.InsertLast(PendingWebhook(eventId, payload));
    }

    void Run()
    {
        while (!stopping) {
            if (queue.IsEmpty() || !CaptureEnabled()) {
                sleep(100);
                continue;
            }
            DeliverFirst();
        }
    }

    void DeliverFirst()
    {
        PendingWebhook@ pending = queue[0];
        uint retries = 0;
        while (true) {
            Net::HttpRequest@ request = CreateRequest(pending.payload);
            request.Start();
            uint startedAt = Time::Now;
            while (!request.Finished() && Time::Now - startedAt < 10000) yield();
            bool timedOut = !request.Finished();
            int status = timedOut ? 0 : request.ResponseCode();
            if (!timedOut && status >= 200 && status < 300) break;
            if (!IsRetryable(status) || retries >= Setting_MaximumRetryCount) {
                LogFailure(pending.eventId, retries + 1, status, timedOut ? "request timed out" : request.String());
                break;
            }
            retries++;
            sleep(RetryDelayMs(request, retries));
        }
        queue.RemoveAt(0);
    }

    Net::HttpRequest@ CreateRequest(const string &in payload)
    {
        Net::HttpRequest@ request = Net::HttpRequest();
        request.Url = Setting_EndpointUrl;
        request.Method = Net::HttpMethod::Post;
        request.Headers["Content-Type"] = "application/json; charset=utf-8";
        request.Headers["Authorization"] = "Bearer " + Setting_AuthenticationToken;
        request.Body = payload;
        return request;
    }

    bool IsRetryable(int status)
    {
        return status == 0 || status == 408 || status == 429 || status >= 500;
    }

    uint RetryDelayMs(Net::HttpRequest@ request, uint retry)
    {
        string retryAfter = request.ResponseHeaders["Retry-After"];
        int seconds = Text::ParseInt(retryAfter);
        if (seconds > 0) return uint(seconds) * 1000;
        int64 retryAt = Time::ParseFormatString("%a, %d %b %Y %H:%M:%S GMT", retryAfter);
        if (retryAt > Time::Stamp) return uint(retryAt - Time::Stamp) * 1000;
        return retry * 5000;
    }

    void LogFailure(const string &in id, uint attempts, int status, const string &in body)
    {
        string excerpt = body.SubStr(0, Math::Min(256, body.Length));
        warn("Dropped webhook event=" + id + " attempts=" + attempts + " status=" + status + " response=" + excerpt);
    }
}
