using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;

namespace StokTakip.Api.Services;

/// <summary>
/// Demo için geçmiş tüketim verisi üretir: tahmin ve anomali özelliklerinin gösterilebilmesi için
/// ürünlere son N günde çıkışlar ekler. Başa eşit miktarda giriş yazdığı için anlık stok DEĞİŞMEZ.
/// Gerçek kullanımda bu veri zaten kendiliğinden birikir; bu sınıf sadece demo/geliştirme içindir.
/// </summary>
public static class DemoHistory
{
    public const string Note = "Demo geçmiş";

    /// <returns>Eklenen hareket sayısı.</returns>
    public static async Task<int> GenerateAsync(AppDbContext db, int userId, int days)
    {
        var todayStart = TurkeyTime.TodayStartUtc;
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
            if (p.OutCount >= 10) continue; // zaten yeterli geçmişi var

            var rng = new Random(p.Id * 7919); // her çalıştırmada aynı sonuç
            var coverDays = rng.Next(8, 46);   // stok 8-45 gün yetecek şekilde bir tüketim hızı
            var baseDaily = Math.Max(1m, Math.Round(Math.Max(p.Stock, 10m) / coverDays, 0));
            var movements = new List<StockMovement>();
            decimal total = 0;

            for (var d = days; d >= 1; d--)
            {
                if (rng.NextDouble() < 0.3) continue; // her gün çıkış olmaz
                var qty = Math.Max(1m, Math.Round(baseDaily * (decimal)(0.6 + rng.NextDouble() * 0.8), 0));
                // TodayStart Türkiye gece yarısı; +8..16 saat = mesai saatleri
                var at = todayStart.AddDays(-d).AddHours(8 + rng.Next(0, 9)).AddMinutes(rng.Next(0, 60));
                movements.Add(Out(p.Id, qty, at, userId, Note));
                total += qty;
            }

            // Bir ürüne, anomali listesinde görünsün diye 2 gün önce olağan dışı büyük bir çıkış.
            if (!anomalyAdded && movements.Count >= 10)
            {
                var qty = baseDaily * 6;
                movements.Add(Out(p.Id, qty, todayStart.AddDays(-2).AddHours(14), userId, "Demo: olağan dışı çıkış"));
                total += qty;
                anomalyAdded = true;
            }

            movements.Add(new StockMovement
            {
                ProductId = p.Id,
                Type = MovementType.In,
                Quantity = total,
                Note = $"{Note}: açılış",
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
