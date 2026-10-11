namespace StokTakip.Api.Services;

/// <summary>appsettings.json → "Insights" bölümü.</summary>
public class InsightOptions
{
    /// <summary>Ortalama tüketim için bakılan gün sayısı.</summary>
    public int WindowDays { get; set; } = 30;

    /// <summary>Tedarikçiden malın gelme süresi (gün). Önerilen kritik seviye bu kadar günü karşılamalı.</summary>
    public int LeadTimeDays { get; set; } = 7;

    /// <summary>Emniyet payı (gün).</summary>
    public int SafetyDays { get; set; } = 3;

    /// <summary>Anomali: ortalamadan kaç standart sapma yukarısı "olağan dışı" sayılır.</summary>
    public double AnomalyZ { get; set; } = 3;

    /// <summary>Anomali kararı için ürünün en az kaç geçmiş çıkışı olmalı (az veriyle yanlış alarm vermesin).</summary>
    public int MinBaselineCount { get; set; } = 5;

    /// <summary>Sayım farkı, sistemdeki stoğun bu oranını aşarsa işaretlenir (0,10 = %10).</summary>
    public double CountDiffRatio { get; set; } = 0.10;

    /// <summary>Son kaç günün hareketleri anomali için taranır.</summary>
    public int LookbackDays { get; set; } = 7;
}

public record OutPoint(DateTime AtUtc, decimal Quantity);

public record ForecastResult(
    decimal AvgDailyOut,
    double? DaysLeft,
    DateTime? StockoutDateUtc,
    decimal SuggestedMinStock,
    int WindowDays);

/// <summary>
/// Tükenme tahmini ve anomali tespiti. Makine öğrenmesi değil, açıklanabilir istatistik:
/// - Tahmin: son N günün ortalama günlük çıkışı → stok kaç gün yeter, ne zaman biter.
/// - Kritik seviye önerisi: günlük tüketim × (tedarik süresi + emniyet payı).
/// - Anomali: ürünün kendi geçmişine göre olağan dışı büyük çıkış (z-skoru) ve büyük sayım farkı.
/// Veritabanından bağımsız saf fonksiyonlar; birim testleriyle doğrulanır.
/// </summary>
public static class StockInsights
{
    /// <param name="stock">Anlık stok.</param>
    /// <param name="outs">Ürünün çıkışları (miktarlar pozitif). Pencere dışındakiler yok sayılır.</param>
    /// <param name="firstMovementUtc">Ürünün ilk hareketi. Yeni ürünlerde pencere kısaltılır ki ortalama düşük çıkmasın.</param>
    public static ForecastResult Forecast(
        decimal stock, IEnumerable<OutPoint> outs, DateTime nowUtc, DateTime? firstMovementUtc, InsightOptions o)
    {
        var historyDays = firstMovementUtc is { } first ? (nowUtc - first).TotalDays : o.WindowDays;
        var windowDays = (int)Math.Clamp(Math.Ceiling(historyDays), 7, o.WindowDays);
        var since = nowUtc.AddDays(-windowDays);

        var totalOut = outs.Where(x => x.AtUtc >= since && x.AtUtc <= nowUtc).Sum(x => x.Quantity);
        var avgDaily = Math.Round(totalOut / windowDays, 3);

        if (avgDaily <= 0)
            return new ForecastResult(0, null, null, 0, windowDays);

        var daysLeft = stock <= 0 ? 0 : Math.Round((double)(stock / avgDaily), 1);
        var suggested = Math.Ceiling(avgDaily * (o.LeadTimeDays + o.SafetyDays));

        return new ForecastResult(avgDaily, daysLeft, nowUtc.AddDays(daysLeft), suggested, windowDays);
    }

    /// <summary>
    /// Çıkış miktarı, ürünün o tarihten önceki çıkışlarının ortalamasından
    /// <see cref="InsightOptions.AnomalyZ"/> standart sapma yukarıdaysa ve ortalamanın en az 2 katıysa olağan dışıdır.
    /// Dönen değer: (olağan dışı mı, ortalamanın kaç katı, ortalama).
    /// </summary>
    public static (bool IsAnomaly, double Ratio, decimal Mean) CheckOut(
        decimal quantity, IReadOnlyCollection<decimal> previousOuts, InsightOptions o)
    {
        if (previousOuts.Count < o.MinBaselineCount) return (false, 0, 0);

        var values = previousOuts.Select(v => (double)v).ToArray();
        var mean = values.Average();
        if (mean <= 0) return (false, 0, 0);

        var std = Math.Sqrt(values.Sum(v => (v - mean) * (v - mean)) / values.Length);
        // Hep aynı miktarda çıkış yapılan üründe std≈0 olur; küçük bir taban koy ki her sapma alarm olmasın.
        var threshold = mean + o.AnomalyZ * Math.Max(std, mean * 0.1);
        var q = (double)quantity;

        var ratio = Math.Round(q / mean, 1);
        return (q > threshold && q >= 2 * mean, ratio, Math.Round((decimal)mean, 2));
    }

    /// <summary>
    /// Sayım farkı (sayılan − sistemdeki), sistemdeki stoğun <see cref="InsightOptions.CountDiffRatio"/> oranını aşarsa işaretlenir.
    /// </summary>
    public static (bool IsAnomaly, double Ratio) CheckCount(decimal delta, decimal counted, InsightOptions o)
    {
        if (Math.Abs(delta) < 1) return (false, 0);
        var before = counted - delta;
        var ratio = (double)(Math.Abs(delta) / Math.Max(before, 1));
        return (ratio >= o.CountDiffRatio, Math.Round(ratio, 2));
    }
}
