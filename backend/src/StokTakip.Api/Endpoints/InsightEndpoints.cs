using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Contracts;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;
using StokTakip.Api.Services;

namespace StokTakip.Api.Endpoints;

/// <summary>Tükenme tahmini, kritik seviye önerisi ve şüpheli hareketler.</summary>
public static class InsightEndpoints
{
    /// <summary>Anomali tabanı için ne kadar geriye bakılır.</summary>
    private const int BaselineDays = 60;

    public static void MapInsightEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/insights", GetInsights).WithTags("Insights").RequireAuthorization();
        app.MapGet("/api/products/{id:int}/forecast", GetProductForecast).WithTags("Insights").RequireAuthorization();
    }

    /// <summary>Özet ekranı için: en yakın tükenecek ürünler (30 gün içinde) ve son günlerin şüpheli hareketleri.</summary>
    private static async Task<IResult> GetInsights(AppDbContext db, InsightOptions o, int days = 30)
    {
        var now = DateTime.UtcNow;
        var horizon = Math.Clamp(days, 1, 365);

        var products = await db.Products.AsNoTracking().Select(ProductEndpoints.ToDto).ToListAsync();
        var firstMovement = await db.StockMovements.AsNoTracking()
            .GroupBy(m => m.ProductId)
            .Select(g => new { ProductId = g.Key, First = g.Min(m => m.CreatedAtUtc) })
            .ToDictionaryAsync(x => x.ProductId, x => x.First);

        var since = now.AddDays(-Math.Max(o.WindowDays, BaselineDays + o.LookbackDays));
        var outs = await db.StockMovements.AsNoTracking()
            .Where(m => m.Type == MovementType.Out && m.CreatedAtUtc >= since)
            .Select(m => new { m.Id, m.ProductId, m.CreatedAtUtc, m.Quantity })
            .ToListAsync();
        var outsByProduct = outs
            .GroupBy(m => m.ProductId)
            .ToDictionary(g => g.Key, g => g.Select(m => new OutPoint(m.CreatedAtUtc, -m.Quantity)).ToList());

        // --- Tükenme tahmini ---
        var stockouts = new List<StockoutDto>();
        foreach (var p in products)
        {
            var points = outsByProduct.GetValueOrDefault(p.Id) ?? [];
            var f = StockInsights.Forecast(p.Stock, points, now, firstMovement.GetValueOrDefault(p.Id), o);
            if (f.DaysLeft is { } left && left <= horizon)
                stockouts.Add(new StockoutDto(p, f.AvgDailyOut, left, f.StockoutDateUtc!.Value, f.SuggestedMinStock));
        }

        // --- Şüpheli hareketler ---
        var lookbackStart = now.AddDays(-o.LookbackDays);
        // Not: Filtre projeksiyondan ÖNCE uygulanmalı; record constructor'ı üzerinden filtre SQL'e çevrilemez.
        var recent = await db.StockMovements.AsNoTracking()
            .Where(m => m.CreatedAtUtc >= lookbackStart && m.Type != MovementType.In)
            .OrderByDescending(m => m.CreatedAtUtc)
            .Select(m => new MovementListItemDto(
                m.Id, m.ProductId, m.Product.Barcode, m.Product.Name, m.Product.Unit,
                m.Type, m.Quantity, m.CountedQuantity, m.Note, m.User.UserName, m.CreatedAtUtc))
            .ToListAsync();

        var anomalies = new List<AnomalyDto>();
        foreach (var m in recent)
        {
            string? reason = null;
            if (m.Type == MovementType.Out)
            {
                var previous = outs
                    .Where(x => x.ProductId == m.ProductId && x.CreatedAtUtc < m.CreatedAtUtc
                                && x.CreatedAtUtc >= m.CreatedAtUtc.AddDays(-BaselineDays))
                    .Select(x => -x.Quantity)
                    .ToList();
                var (isAnomaly, ratio, mean) = StockInsights.CheckOut(-m.Quantity, previous, o);
                if (isAnomaly)
                    reason = $"Normalin {Tr(ratio, "0.#")} katı çıkış (ortalama {Tr((double)mean, "0.##")} {m.Unit})";
            }
            else if (m.Type == MovementType.Count && m.CountedQuantity is { } counted)
            {
                var (isAnomaly, ratio) = StockInsights.CheckCount(m.Quantity, counted, o);
                if (isAnomaly)
                    reason = $"Sayım farkı {Tr((double)m.Quantity, "+0.##;-0.##")} {m.Unit} (stoğun %{Tr(ratio * 100, "0")})";
            }

            if (reason is not null)
                anomalies.Add(new AnomalyDto(m.Id, m.ProductId, m.Barcode, m.ProductName, m.Unit, m.Type,
                    m.Quantity, m.CountedQuantity, m.UserName, m.CreatedAtUtc, reason));
        }

        return Results.Ok(new InsightsDto(
            stockouts.OrderBy(s => s.DaysLeft).Take(10).ToList(),
            anomalies.OrderByDescending(a => a.CreatedAtUtc).Take(10).ToList(),
            o.WindowDays,
            o.LeadTimeDays));
    }

    /// <summary>Sunucunun kültüründen bağımsız Türkçe ondalık: 6,2 (container'da varsayılan kültür invariant).</summary>
    private static string Tr(double value, string format) =>
        value.ToString(format, System.Globalization.CultureInfo.InvariantCulture).Replace('.', ',');

    /// <summary>Ürün ekranı için: günlük ortalama çıkış, kaç gün yeter, önerilen kritik seviye.</summary>
    private static async Task<IResult> GetProductForecast(int id, AppDbContext db, InsightOptions o)
    {
        var product = await db.Products.AsNoTracking().Where(p => p.Id == id).Select(ProductEndpoints.ToDto).SingleOrDefaultAsync();
        if (product is null)
            return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Ürün bulunamadı.");

        var now = DateTime.UtcNow;
        var since = now.AddDays(-o.WindowDays);
        var outs = await db.StockMovements.AsNoTracking()
            .Where(m => m.ProductId == id && m.Type == MovementType.Out && m.CreatedAtUtc >= since)
            .Select(m => new OutPoint(m.CreatedAtUtc, -m.Quantity))
            .ToListAsync();
        var first = await db.StockMovements.AsNoTracking()
            .Where(m => m.ProductId == id)
            .MinAsync(m => (DateTime?)m.CreatedAtUtc);

        var f = StockInsights.Forecast(product.Stock, outs, now, first, o);
        return Results.Ok(new ProductForecastDto(
            f.AvgDailyOut, f.DaysLeft, f.StockoutDateUtc, f.SuggestedMinStock, f.WindowDays, o.LeadTimeDays, o.SafetyDays));
    }
}
