namespace UtcClockService
{
    int64 AnchorEpochMs = 0;
    uint64 AnchorMonotonicMs = 0;

    void Initialize()
    {
        AnchorEpochMs = Time::Stamp * 1000;
        AnchorMonotonicMs = Time::Now;
        startnew(Calibrate);
    }

    int64 CurrentMs()
    {
        return AnchorEpochMs + int64(Time::Now - AnchorMonotonicMs);
    }

    string Format(int64 epochMs)
    {
        int64 seconds = epochMs / 1000;
        int milliseconds = int(epochMs % 1000);
        if (milliseconds < 0) milliseconds += 1000;
        return Time::FormatStringUTC("%Y-%m-%dT%H:%M:%S", seconds) +
            "." + Text::Format("%03d", milliseconds) + "Z";
    }

    void Calibrate()
    {
        int64 previousStamp = Time::Stamp;
        while (Time::Stamp == previousStamp) yield();
        AnchorEpochMs = Time::Stamp * 1000;
        AnchorMonotonicMs = Time::Now;
    }
}
