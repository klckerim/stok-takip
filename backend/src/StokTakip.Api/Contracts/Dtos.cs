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

public record ProductForecastDto(
    decimal AvgDailyOut,
    double? DaysLeft,
    DateTime? StockoutDateUtc,
    decimal SuggestedMinStock,
    int WindowDays,
    int LeadTimeDays,
    int SafetyDays);

public record StockoutDto(ProductDto Product, decimal AvgDailyOut, double DaysLeft, DateTime StockoutDateUtc, decimal SuggestedMinStock);

public record AnomalyDto(
    long MovementId,
    int ProductId,
    string Barcode,
    string ProductName,
    string Unit,
    MovementType Type,
    decimal Quantity,
    decimal? CountedQuantity,
    string UserName,
    DateTime CreatedAtUtc,
    string Reason);

public record InsightsDto(List<StockoutDto> Stockouts, List<AnomalyDto> Anomalies, int WindowDays, int LeadTimeDays);

/// <summary>ML talep modeli: ne zaman, kaç örnekle eğitildi ve test döneminde ne kadar isabetli oldu.</summary>
/// <param name="TestMae">Son 14 günde (eğitimde görülmemiş) günlük ortalama mutlak hata.</param>
/// <param name="BaselineMae">Aynı dönemde "son 28 gün ortalaması" tahmininin hatası; model bunu geçmeli.</param>
/// <param name="DailyCoverage">Günlük %90 aralığın test döneminde gerçek değeri kapsama oranı.</param>
/// <param name="TotalHits">14 günlük toplam aralığı test döneminde kaç üründe tuttu (<paramref name="TotalCount"/> içinden).</param>
/// <param name="UsesDemoData">Eğitim verisinde sentetik demo geçmişi var; ekranda belirtilir.</param>
public record DemandModelInfoDto(
    bool Trained, string? Reason, string Algorithm, DateTime? TrainedAtUtc, long TrainingMs,
    int TrainingRows, int ProductCount, int HistoryDays, double ConfidenceLevel, bool Calibrated,
    double? TestMae, double? BaselineMae, double? DailyCoverage, int? TotalHits, int? TotalCount,
    bool UsesDemoData = false);

public record DemandDayDto(DateOnly Date, decimal Quantity);

public record DemandForecastDayDto(DateOnly Date, decimal Forecast, decimal Lower, decimal Upper);

/// <param name="History">Son 28 tam günün gerçek çıkışları (grafik için).</param>
/// <param name="Forecast">Bugünden itibaren 14 günün tahmini ve %90 aralığı.</param>
/// <param name="StockoutDate">Beklenen çıkışlara göre stoğun biteceği gün (14 gün içindeyse).</param>
public record DemandForecastDto(
    bool Available, string? Reason, List<DemandDayDto> History, List<DemandForecastDayDto> Forecast,
    decimal Total, decimal TotalLower, decimal TotalUpper, DateOnly? StockoutDate, DemandModelInfoDto Model);
