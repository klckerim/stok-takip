using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;
using StokTakip.Api.Services.Demand;

namespace StokTakip.Api.Endpoints;

/// <summary>ML.NET talep tahmini.</summary>
public static class DemandEndpoints
{
    public static void MapDemandEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/products/{id:int}/demand-forecast", GetForecast).WithTags("ML").RequireAuthorization();
        app.MapGet("/api/ml/demand-model", (DemandForecaster f) => Results.Ok(f.Info)).WithTags("ML").RequireAuthorization();
        app.MapPost("/api/ml/demand-model/train", Train)
            .WithTags("ML")
            .RequireAuthorization(p => p.RequireRole(Roles.Admin));
    }

    /// <summary>Önümüzdeki 14 günün günlük çıkış tahmini, %90 aralığı ve modelin test başarısı.</summary>
    private static async Task<IResult> GetForecast(int id, AppDbContext db, DemandForecaster forecaster, CancellationToken ct)
    {
        var product = await db.Products.AsNoTracking().Where(p => p.Id == id).Select(ProductEndpoints.ToDto).SingleOrDefaultAsync(ct);
        if (product is null)
            return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Ürün bulunamadı.");

        return Results.Ok(await forecaster.ForecastAsync(id, product.Stock, ct));
    }

    /// <summary>Modeli hemen yeniden eğitir (normalde açılışta ve 6 saatte bir kendiliğinden eğitilir).</summary>
    private static async Task<IResult> Train(DemandForecaster forecaster, CancellationToken ct) =>
        Results.Ok(await forecaster.TrainAsync(ct));
}
