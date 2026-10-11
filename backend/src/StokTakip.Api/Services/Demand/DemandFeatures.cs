namespace StokTakip.Api.Services.Demand;

/// <summary>Bir ürünün günlük çıkış serisi (Türkiye takvimi). <c>Daily[0]</c> = <see cref="FirstDay"/>.</summary>
public sealed record DailySeries(int ProductId, DateOnly FirstDay, float[] Daily)
{
    public DateOnly LastDay => FirstDay.AddDays(Daily.Length - 1);
    public int IndexOf(DateOnly day) => day.DayNumber - FirstDay.DayNumber;
    public float At(DateOnly day) => Daily[IndexOf(day)];
}

/// <summary>Bir eğitim/değerlendirme örneği: "origin gününde bilinenlerle, Target günün çıkışı".</summary>
public sealed record DemandExample(int ProductId, DateOnly Origin, DateOnly Target, float[] Features, float Label, float Baseline);

/// <summary>
/// Talep tahmini için özellik mühendisliği. Saf fonksiyonlar; veritabanı ve ML.NET'ten bağımsız, birim testli.
///
/// Problem, zaman serisi yerine denetimli regresyon olarak kurulur (perakende talep tahmininde yaygın yaklaşım):
/// "origin" = tahmin anındaki son tam gün, "target" = origin + 1..14 gün.
/// Özellikler YALNIZCA origin ve öncesine bakar; gelecekten bilgi sızmaz.
/// Tüm ürünler tek (global) modelle eğitilir: ürün başına az veri olsa da toplamda yeterli örnek olur,
/// ölçek farkı log(ortalama) özellikleriyle taşınır.
/// </summary>
public static class DemandFeatures
{
    /// <summary>Özellikler için geriye bakılan gün sayısı. Bir ürün en az bu kadar geçmiş ister.</summary>
    public const int Lookback = 28;

    /// <summary>Kaç gün ileri tahmin edilir.</summary>
    public const int Horizon = 14;

    /// <summary>
    /// 0-6: hedef günün haftanın günü (one-hot, Pazartesi = 0)
    /// 7: log(1 + son 7 gün ortalaması)    → yakın dönem seviyesi
    /// 8: log(1 + son 28 gün ortalaması)   → genel seviye
    /// 9: log(1 + son 4 haftada hedefle aynı gün ortalaması) → ürüne özgü haftalık desen
    /// 10: son 28 günde çıkışsız gün oranı → seyrek talep
    /// </summary>
    public const int Count = 11;

    public static readonly string[] Names =
        ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz", "log_ort7", "log_ort28", "log_aynigun4", "sifir_orani"];

    public static int DowIndex(DayOfWeek day) => ((int)day + 6) % 7;

    /// <summary>Çıkışları günlere toplar. Aralık dışındakiler yok sayılır.</summary>
    public static DailySeries BuildSeries(int productId, DateOnly firstDay, DateOnly lastDay, IEnumerable<(DateOnly Day, float Quantity)> outs)
    {
        var daily = new float[Math.Max(0, lastDay.DayNumber - firstDay.DayNumber + 1)];
        foreach (var (day, qty) in outs)
        {
            var i = day.DayNumber - firstDay.DayNumber;
            if (i >= 0 && i < daily.Length) daily[i] += qty;
        }
        return new DailySeries(productId, firstDay, daily);
    }

    /// <summary>Origin günü dahil geriye <see cref="Lookback"/> günlük veri var mı?</summary>
    public static bool HasWindow(DailySeries s, DateOnly origin)
    {
        var i = s.IndexOf(origin);
        return i >= Lookback - 1 && i < s.Daily.Length;
    }

    /// <param name="baseline">Karşılaştırma için basit tahmin: son 28 günün ortalaması.</param>
    public static float[] Build(DailySeries s, DateOnly origin, DateOnly target, out float baseline)
    {
        var end = s.IndexOf(origin);
        var start = end - Lookback + 1;
        if (start < 0 || end >= s.Daily.Length)
            throw new ArgumentOutOfRangeException(nameof(origin), "Origin için yeterli geçmiş yok.");

        float sum28 = 0, sum7 = 0, sameSum = 0;
        int sameCount = 0, zeros = 0;
        var targetDow = target.DayOfWeek;

        for (var i = start; i <= end; i++)
        {
            var v = s.Daily[i];
            sum28 += v;
            if (i > end - 7) sum7 += v;
            if (v == 0) zeros++;
            if (s.FirstDay.AddDays(i).DayOfWeek == targetDow)
            {
                sameSum += v;
                sameCount++;
            }
        }

        var mean28 = sum28 / Lookback;
        var mean7 = sum7 / 7;
        var sameMean = sameCount > 0 ? sameSum / sameCount : mean28;
        baseline = mean28;

        var f = new float[Count];
        f[DowIndex(targetDow)] = 1;
        f[7] = MathF.Log(1 + mean7);
        f[8] = MathF.Log(1 + mean28);
        f[9] = MathF.Log(1 + sameMean);
        f[10] = zeros / (float)Lookback;
        return f;
    }

    /// <summary>Hedef günü <paramref name="cutoff"/>'u geçmeyen tüm (origin, ufuk) örnekleri.</summary>
    /// <param name="originStep">Çok büyük veride her N. günü origin al (bellek/süre sınırı).</param>
    public static List<DemandExample> TrainingExamples(IEnumerable<DailySeries> series, DateOnly cutoff, int originStep = 1)
    {
        var list = new List<DemandExample>();
        foreach (var s in series)
        {
            var last = cutoff < s.LastDay ? cutoff : s.LastDay;
            for (var o = s.FirstDay.AddDays(Lookback - 1); o < last; o = o.AddDays(originStep))
            {
                for (var h = 1; h <= Horizon; h++)
                {
                    var t = o.AddDays(h);
                    if (t > last) break;
                    var f = Build(s, o, t, out var b);
                    list.Add(new DemandExample(s.ProductId, o, t, f, s.At(t), b));
                }
            }
        }
        return list;
    }

    /// <summary>Origin'den sonraki 14 günün gerçek değerleri bilinen ürünler için değerlendirme örnekleri.</summary>
    public static List<DemandExample> EvaluationExamples(IEnumerable<DailySeries> series, DateOnly origin)
    {
        var list = new List<DemandExample>();
        foreach (var s in series)
        {
            if (!HasWindow(s, origin) || s.LastDay < origin.AddDays(Horizon)) continue;
            for (var h = 1; h <= Horizon; h++)
            {
                var t = origin.AddDays(h);
                var f = Build(s, origin, t, out var b);
                list.Add(new DemandExample(s.ProductId, origin, t, f, s.At(t), b));
            }
        }
        return list;
    }

    /// <summary>Eğitim örneği sayısı tahmini; <paramref name="maxRows"/>'u aşarsa origin adımı büyütülür.</summary>
    public static int OriginStep(IEnumerable<DailySeries> series, int maxRows)
    {
        long rows = series.Sum(s => (long)Math.Max(0, s.Daily.Length - Lookback) * Horizon);
        return (int)Math.Max(1, Math.Ceiling(rows / (double)maxRows));
    }

    /// <summary>
    /// Sayım verisi için ölçeklenmiş hata: |gerçek − tahmin| / √(tahmin + 1).
    /// Poisson'da varyans ortalamayla büyür; bu ölçekleme sayesinde tek bir eşik hem 2 hem 200 adetlik ürüne uyar.
    /// </summary>
    public static double ScaledError(double actual, double predicted) =>
        Math.Abs(actual - predicted) / Math.Sqrt(Math.Max(predicted, 0) + 1);

    /// <summary>Doğrusal aralıklı yüzdelik (numpy varsayılanı ile aynı).</summary>
    public static double Quantile(IEnumerable<double> values, double p)
    {
        var v = values.OrderBy(x => x).ToArray();
        if (v.Length == 0) throw new ArgumentException("Boş liste.", nameof(values));
        var pos = (v.Length - 1) * p;
        var lo = (int)Math.Floor(pos);
        var hi = (int)Math.Ceiling(pos);
        return v[lo] + (v[hi] - v[lo]) * (pos - lo);
    }
}
