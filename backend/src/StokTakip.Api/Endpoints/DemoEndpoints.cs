using System.Security.Claims;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;
using StokTakip.Api.Services;
using StokTakip.Api.Services.Demand;

namespace StokTakip.Api.Endpoints;

/// <summary>Sadece geliştirme ortamında: mevcut veritabanına demo geçmişi ekler (öncekini silip yeniden üretir).</summary>
public static class DemoEndpoints
{
    public static void MapDemoEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/demo/history", Generate)
            .WithTags("Demo")
            .RequireAuthorization(p => p.RequireRole(Roles.Admin));
    }

    private static async Task<IResult> Generate(AppDbContext db, ClaimsPrincipal user, IHostEnvironment env, DemandForecaster forecaster, int days = 120)
    {
        if (!env.IsDevelopment()) return Results.NotFound();
        var created = await DemoHistory.GenerateAsync(db, user.UserId(), Math.Clamp(days, 14, 180));
        var model = await forecaster.TrainAsync(); // yeni geçmişle ML modelini hemen yeniden eğit
        return Results.Ok(new
        {
            created,
            message = created == 0 ? "Ürünlerin zaten yeterli gerçek geçmişi var." : "Demo geçmişi yeniden üretildi; anlık stoklar değişmedi.",
            model
        });
    }
}
