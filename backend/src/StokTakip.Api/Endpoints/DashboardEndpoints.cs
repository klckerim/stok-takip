using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Contracts;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;
using StokTakip.Api.Services;

namespace StokTakip.Api.Endpoints;

public static class DashboardEndpoints
{
    public static void MapDashboardEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/dashboard", Get).WithTags("Dashboard").RequireAuthorization();
    }

    /// <summary>Özet ekranı: ürün ve kritik sayısı, bugünün hareketleri, kritik ürünler, son hareketler.</summary>
    private static async Task<IResult> Get(AppDbContext db)
    {
        var todayStart = TurkeyTime.TodayStartUtc;

        var productCount = await db.Products.CountAsync();

        var criticalQuery = db.Products.AsNoTracking()
            .Where(p => p.MinStock > 0 && p.Movements.Sum(m => m.Quantity) <= p.MinStock);
        var criticalCount = await criticalQuery.CountAsync();
        var criticalProducts = await criticalQuery
            .OrderBy(p => p.Movements.Sum(m => m.Quantity) - p.MinStock) // en çok açığı olan önce
            .Select(ProductEndpoints.ToDto)
            .Take(5)
            .ToListAsync();

        var todayByType = await db.StockMovements.AsNoTracking()
            .Where(m => m.CreatedAtUtc >= todayStart)
            .GroupBy(m => m.Type)
            .Select(g => new { Type = g.Key, Count = g.Count() })
            .ToListAsync();
        int Today(MovementType t) => todayByType.FirstOrDefault(x => x.Type == t)?.Count ?? 0;

        var lastMovements = await MovementEndpoints.ListQuery(db).Take(10).ToListAsync();

        return Results.Ok(new DashboardDto(
            productCount,
            criticalCount,
            Today(MovementType.In),
            Today(MovementType.Out),
            Today(MovementType.Count),
            criticalProducts,
            lastMovements));
    }
}
