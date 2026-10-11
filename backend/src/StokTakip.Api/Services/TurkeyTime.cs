namespace StokTakip.Api.Services;

/// <summary>Raporlar ve "bugün" hesabı için Türkiye saati. 2016'dan beri sabit UTC+3.</summary>
public static class TurkeyTime
{
    public static readonly TimeZoneInfo Zone = Find();

    private static TimeZoneInfo Find()
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById("Europe/Istanbul"); }
        catch (Exception) { return TimeZoneInfo.CreateCustomTimeZone("TRT", TimeSpan.FromHours(3), "Türkiye", "Türkiye"); }
    }

    public static DateTime ToLocal(DateTime utc) =>
        TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utc, DateTimeKind.Utc), Zone);

    public static DateTime Now => ToLocal(DateTime.UtcNow);

    /// <summary>Türkiye'de bugünün başlangıcı, UTC olarak.</summary>
    public static DateTime TodayStartUtc => TimeZoneInfo.ConvertTimeToUtc(Now.Date, Zone);
}
