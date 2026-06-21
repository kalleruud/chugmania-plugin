string CreateUuidV4()
{
    string hex = "0123456789abcdef";
    string value;
    for (uint i = 0; i < 32; i++) value += hex.SubStr(Math::Rand(0, 16), 1);
    value = value.SubStr(0, 12) + "4" + value.SubStr(13);
    uint variant = Math::Rand(8, 12);
    value = value.SubStr(0, 16) + hex.SubStr(variant, 1) + value.SubStr(17);
    return value.SubStr(0, 8) + "-" + value.SubStr(8, 4) + "-" +
        value.SubStr(12, 4) + "-" + value.SubStr(16, 4) + "-" + value.SubStr(20);
}

string OccurredAtUtc()
{
    string millis = tostring(Time::Now % 1000);
    while (millis.Length < 3) millis = "0" + millis;
    return Time::FormatStringUTC("%Y-%m-%dT%H:%M:%S", Time::Stamp) + "." + millis + "Z";
}
