using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;

namespace StokTakip.Api.Services;

/// <summary>
/// Demo için SENTETİK geçmiş tüketim verisi üretir: tahmin, anomali ve ML talep tahmini
/// özelliklerinin gösterilebilmesi için ürünlere son N günde çıkışlar ekler.
/// Gerçekçi olsun diye haftalık desen (pazartesi yoğun, cumartesi yarım gün, pazar kapalı),
/// ürüne özgü artan/azalan eğilim ve gürültü içerir.
/// Başa eşit miktarda giriş yazdığı için anlık stok DEĞİŞMEZ.
/// Gerçek kullanımda bu veri zaten kendiliğinden birikir; bu sınıf sadece demo/geliştirme içindir.
/// </summary>
public static class DemoHistory
{
    public const string Note = "Demo geçmiş";
    public const string OpeningNote = "Demo geçmiş: açılış";
    public const string AnomalyNote = "Demo: olağan dışı çıkış";

    /// <summary>Haftanın günü çarpanı (Pazartesi..Pazar). Pazar depo kapalı.</summary>
    private static readonly double[] WeekdayFactor = [1.25, 1.10, 1.00, 1.00, 1.15, 0.55, 0.0];

    /// <summary>
    /// Önceki demo geçmişini siler ve yeniden üretir (tekrar çağrılabilir; sonuç hep aynı).
    /// Gerçek hareketleri olan ürünlere (10+ gerçek çıkış) dokunmaz.
    /// </summary>
    /// <returns>Eklenen hareket sayısı.</returns>
    public static async Task<int> GenerateAsync(AppDbContext db, int userId, int days)
    {
        // Önceki demo hareketleri toplamda sıfırdır (açılış girişi = çıkışların toplamı); silmek stoğu değiştirmez.
        await db.StockMovements
            .Where(m => m.Note == Note || m.Note == OpeningNote || m.Note == AnomalyNote)
            .ExecuteDeleteAsync();

        var todayStart = TurkeyTime.TodayStartUtc;
        var today = DateOnly.FromDateTime(TurkeyTime.Now);
        var products = await db.Products
            .Select(p => new
            {
                p.Id,
                Stock = p.Movements.Sum(m => m.Quantity),
                OutCount = p.Movements.Count(m => m.Type == MovementType.Out)
            })
            .OrderByDescending(p => p.Stock)
            .ToListAsync();

        var created = 0;
        var anomalyAdded = false;

        foreach (var p in products)
        {
            if (p.OutCount >= 10) continue; // gerçek geçmişi var

            var rng = new Random(p.Id * 7919);  // her çalıştırmada aynı sonuç
            var coverDays = rng.Next(8, 46);    // stok 8-45 gün yetecek şekilde bir tüketim hızı
            var baseDaily = Math.Max(1m, Math.Round(Math.Max(p.Stock, 10m) / coverDays, 0));
            var trend = -0.25 + rng.NextDouble() * 0.60; // dönem boyunca %-25..%+35
            var movements = new List<StockMovement>();
            decimal total = 0;

            for (var d = days; d >= 1; d--)
            {
                var day = today.AddDays(-d);
                var weekday = WeekdayFactor[((int)day.DayOfWeek + 6) % 7];
                var trendFactor = 1 + trend * (days - d) / days;
                var noise = 0.65 + rng.NextDouble() * 0.70;
                if (weekday == 0 || rng.NextDouble() < 0.12) continue; // pazar kapalı; bazı günler çıkış olmaz

                var qty = Math.Max(1m, Math.Round(baseDaily * (decimal)(weekday * trendFactor * noise), 0));
                // TodayStart Türkiye gece yarısı; +8..16 saat = mesai saatleri
                var at = todayStart.AddDays(-d).AddHours(8 + rng.Next(0, 9)).AddMinutes(rng.Next(0, 60));
                movements.Add(Out(p.Id, qty, at, userId, Note));
                total += qty;
            }

            // Bir ürüne, anomali listesinde görünsün diye 2 gün önce olağan dışı büyük bir çıkış.
            if (!anomalyAdded && movements.Count >= 10)
            {
                var qty = baseDaily * 6;
                movements.Add(Out(p.Id, qty, todayStart.AddDays(-2).AddHours(14), userId, AnomalyNote));
                total += qty;
                anomalyAdded = true;
            }

            movements.Add(new StockMovement
            {
                ProductId = p.Id,
                Type = MovementType.In,
                Quantity = total,
                Note = OpeningNote,
                UserId = userId,
                CreatedAtUtc = todayStart.AddDays(-days - 1).AddHours(9)
            });

            db.StockMovements.AddRange(movements);
            created += movements.Count;
        }

        await db.SaveChangesAsync();
        return created;
    }

    private static StockMovement Out(int productId, decimal qty, DateTime atUtc, int userId, string note) => new()
    {
        ProductId = productId,
        Type = MovementType.Out,
        Quantity = -qty,
        Note = note,
        UserId = userId,
        CreatedAtUtc = atUtc
    };
}
