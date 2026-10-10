using StokTakip.Api.Domain;

namespace StokTakip.Api.Contracts;

public record LoginRequest(string UserName, string Password);
public record LoginResponse(string Token, string FullName, string Role, DateTime ExpiresAtUtc);

public record ProductDto(int Id, string Barcode, string Name, string Unit, decimal Stock, decimal MinStock)
{
    public bool IsCritical => MinStock > 0 && Stock <= MinStock;
}

public record CreateProductRequest(
    string Barcode,
    string Name,
    string Unit,
    decimal MinStock = 0,
    decimal InitialStock = 0);

public record UpdateProductRequest(string Name, string Unit, decimal MinStock);

public record CreateMovementRequest(
    int ProductId,
    MovementType Type,
    decimal Quantity,
    string? Note,
    Guid? ClientRequestId);

public record MovementDto(
    long Id,
    MovementType Type,
    decimal Quantity,
    decimal? CountedQuantity,
    string? Note,
    string UserName,
    DateTime CreatedAtUtc);

public record MovementResult(MovementDto Movement, decimal NewStock);
