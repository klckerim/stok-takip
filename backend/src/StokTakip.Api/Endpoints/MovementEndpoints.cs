using System.Data;
using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Contracts;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;
using StokTakip.Api.Services;

namespace StokTakip.Api.Endpoints;

public static class MovementEndpoints
{
    public static void MapMovementEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/movements", Create)
            .WithTags("Movements")
            .RequireAuthorization();
    }

    /// <summary>Çevrimdışı kaydedilen hareket en fazla bu kadar geriye tarihlenebilir.</summary>
    private static readonly TimeSpan MaxOfflineAge = TimeSpan.FromDays(30);

    /// <summary>
    /// Giriş, çıkış veya sayım kaydı.
    /// - In / Out: Quantity = hareket miktarı (pozitif).
    /// - Count: Quantity = sayılan miktar; stoka etkisi (sayılan - mevcut) olarak yazılır.
    /// - OccurredAtUtc: Mobil çevrimdışıyken kaydettiyse işlemin gerçek zamanı. Verilmezse şimdi.
    /// </summary>
    private static async Task<IResult> Create(CreateMovementRequest req, AppDbContext db, ClaimsPrincipal user)
    {
        if (req.Type is not (MovementType.In or MovementType.Out or MovementType.Count))
            return Invalid("type", "Geçersiz hareket tipi.");
        if (req.Type != MovementType.Count && req.Quantity <= 0)
            return Invalid("quantity", "Miktar sıfırdan büyük olmalı.");
        if (req.Type == MovementType.Count && req.Quantity < 0)
            return Invalid("quantity", "Sayılan miktar negatif olamaz.");

        var now = DateTime.UtcNow;
        var occurredAt = req.OccurredAtUtc is { } t
            ? (t.Kind == DateTimeKind.Local ? t.ToUniversalTime() : DateTime.SpecifyKind(t, DateTimeKind.Utc))
            : now;
        if (occurredAt > now) occurredAt = now; // cihaz saati ileri olabilir
        if (occurredAt < now - MaxOfflineAge)
            return Invalid("occurredAtUtc", "Kayıt 30 günden eski; gönderilemez.");

        // Aynı istek ikinci kez geldiyse ilk sonucu döndür (idempotency).
        if (req.ClientRequestId is { } requestId)
        {
            var existing = await FindByRequestId(db, requestId);
            if (existing is not null) return Results.Ok(existing);
        }

        if (!await db.Products.AnyAsync(p => p.Id == req.ProductId))
            return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Ürün bulunamadı.");

        // Serializable: aynı anda iki çıkış yapılırsa stok eksiye düşmesin.
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable);

        var current = await db.StockMovements
            .Where(m => m.ProductId == req.ProductId)
            .SumAsync(m => m.Quantity);

        var movement = new StockMovement
        {
            ProductId = req.ProductId,
            Type = req.Type,
            Note = string.IsNullOrWhiteSpace(req.Note) ? null : req.Note.Trim(),
            UserId = user.UserId(),
            ClientRequestId = req.ClientRequestId,
            CreatedAtUtc = occurredAt
        };

        switch (req.Type)
        {
            case MovementType.In:
                movement.Quantity = req.Quantity;
                break;
            case MovementType.Out:
                if (req.Quantity > current)
                    return Results.Problem(
                        statusCode: StatusCodes.Status409Conflict,
                        title: "Yetersiz stok.",
                        detail: $"Mevcut stok {current:0.###}, çıkış {req.Quantity:0.###}.");
                movement.Quantity = -req.Quantity;
                break;
            case MovementType.Count:
                movement.CountedQuantity = req.Quantity;
                movement.Quantity = req.Quantity - current;
                break;
        }

        db.StockMovements.Add(movement);
        try
        {
            await db.SaveChangesAsync();
            await tx.CommitAsync();
        }
        catch (DbUpdateException) when (req.ClientRequestId is { } racedRequestId)
        {
            // Aynı ClientRequestId ile paralel gelen istek bizden önce yazdı.
            await tx.RollbackAsync();
            db.ChangeTracker.Clear();
            var raced = await FindByRequestId(db, racedRequestId);
            if (raced is not null) return Results.Ok(raced);
            throw;
        }

        var userName = user.FindFirstValue(ClaimTypes.Name) ?? "";
        var dto = new MovementDto(movement.Id, movement.Type, movement.Quantity, movement.CountedQuantity,
            movement.Note, userName, movement.CreatedAtUtc);

        return Results.Created($"/api/products/{req.ProductId}/movements",
            new MovementResult(dto, current + movement.Quantity));
    }

    private static IResult Invalid(string field, string message) =>
        Results.ValidationProblem(new Dictionary<string, string[]> { [field] = [message] });

    private static async Task<MovementResult?> FindByRequestId(AppDbContext db, Guid requestId)
    {
        var m = await db.StockMovements.AsNoTracking()
            .Where(x => x.ClientRequestId == requestId)
            .Select(x => new
            {
                Dto = new MovementDto(x.Id, x.Type, x.Quantity, x.CountedQuantity, x.Note, x.User.UserName, x.CreatedAtUtc),
                x.ProductId
            })
            .SingleOrDefaultAsync();

        if (m is null) return null;

        var stock = await db.StockMovements.Where(x => x.ProductId == m.ProductId).SumAsync(x => x.Quantity);
        return new MovementResult(m.Dto, stock);
    }
}
