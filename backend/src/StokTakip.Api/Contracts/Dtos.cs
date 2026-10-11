using StokTakip.Api.Domain;

namespace StokTakip.Api.Contracts;

public record LoginRequest(string UserName, string Password);
public record LoginResponse(string Token, string FullName, string Role, DateTime ExpiresAtUtc);

public record ProductDto(
    int Id,
    string Barcode,
    string Name,
    string Unit,
    decimal Stock,
    decimal MinStock,
    int? CategoryId = null,
    string? CategoryName = null)
{
    public bool IsCritical => MinStock > 0 && Stock <= MinStock;
}

public record CreateProductRequest(
    string Barcode,
    string Name,
    string Unit,
    decimal MinStock = 0,
    decimal InitialStock = 0,
    int? CategoryId = null);

public record UpdateProductRequest(string Name, string Unit, decimal MinStock, int? CategoryId = null);

public record CategoryDto(int Id, string Name, int ProductCount);
public record CreateCategoryRequest(string Name);

public record CreateMovementRequest(
    int ProductId,
    MovementType Type,
    decimal Quantity,
    string? Note,
    Guid? ClientRequestId,
    DateTime? OccurredAtUtc = null);

public record MovementDto(
    long Id,
    MovementType Type,
    decimal Quantity,
    decimal? CountedQuantity,
    string? Note,
    string UserName,
    DateTime CreatedAtUtc);

public record MovementResult(MovementDto Movement, decimal NewStock);

public record MovementListItemDto(
    long Id,
    int ProductId,
    string Barcode,
    string ProductName,
    string Unit,
    MovementType Type,
    decimal Quantity,
    decimal? CountedQuantity,
    string? Note,
    string UserName,
    DateTime CreatedAtUtc);

public record DashboardDto(
    int ProductCount,
    int CriticalCount,
    int TodayIn,
    int TodayOut,
    int TodayCount,
    List<ProductDto> CriticalProducts,
    List<MovementListItemDto> LastMovements);
