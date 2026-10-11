using System.Security.Claims;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;
using StokTakip.Api.Services;

namespace StokTakip.Api.Endpoints;

/// <summary>Sadece geliştirme ortamında: mevcut veritabanına demo geçmişi ekler.</summary>
public static class DemoEndpoints
{
    public static void MapDemoEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/demo/history", Generate)
            .WithTags("Demo")
            .RequireAuthorization(p => p.RequireRole(Roles.Admin));
    }

    private static async Task<IResult> Generate(AppDbContext db, ClaimsPrincipal user, IHostEnvironment env, int days = 60)
    {
        if (!env.IsDevelopment()) return Results.NotFound();
        var created = await DemoHistory.GenerateAsync(db, user.UserId(), Math.Clamp(days, 14, 180));
        return Results.Ok(new { created, message = created == 0 ? "Ürünlerin zaten yeterli geçmişi var." : "Demo geçmişi eklendi; anlık stoklar değişmedi." });
    }
}
