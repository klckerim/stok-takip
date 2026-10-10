using StokTakip.Api.Domain;

namespace StokTakip.Api.Contracts;

public record LoginRequest(string UserName, string Password);
public record LoginResponse(string Token, string FullName, string Role, DateTime ExpiresAtUtc);

public record ProductDto(int Id, string Barcode, string Name, string Unit, decimal Stock);
public record CreateProductRequest(string Barcode, string Name, string Unit);

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
