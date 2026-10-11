using Microsoft.EntityFrameworkCore;
using Microsoft.ML;
using StokTakip.Api.Contracts;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;

namespace StokTakip.Api.Services.Demand;

/// <summary>
/// Talep tahmini servisi (singleton). Model bellekte tutulur; arka planda periyodik ve
/// demo geçmişi üretilince yeniden eğitilir. Tahmin isteği modeli eğitmez, sadece kullanır
/// (model henüz yoksa bir kez eğitir). Eğitim aynı anda tek kez çalışır.
/// </summary>
public sealed class DemandForecaster(IServiceScopeFactory scopes, ILogger<DemandForecaster> logger)
{
    /// <summary>Eğitimde geriye bakılan en fazla gün (yaklaşık 6 ay + özellik penceresi).</summary>
    public const int MaxHistoryDays = 180 + DemandFeatures.Lookback;

    private readonly MLContext _ml = new(seed: 1);
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile TrainedDemandModel? _current;
    private volatile DemandModelInfoDto _info = NotTrained("Model henüz eğitilmedi.");

    public DemandModelInfoDto Info => _info;

    public async Task<DemandModelInfoDto> TrainAsync(CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            using var scope = scopes.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var lastDay = LastCompleteDay();
            var series = await LoadSeriesAsync(db, null, lastDay, ct);
            var usesDemoData = await db.StockMovements.AnyAsync(m => m.Note == DemoHistory.Note, ct);

            // ML.NET eğitimi CPU işi; istek iş parçacığını meşgul etmesin.
            var (result, reason) = await Task.Run(() => DemandTraining.Run(_ml, series, lastDay), ct);
            if (result is null)
            {
                _current = null;
                _info = NotTrained(reason!);
                logger.LogInformation("Talep modeli eğitilmedi: {Reason}", reason);
            }
            else
            {
                result = result with { Info = result.Info with { UsesDemoData = usesDemoData } };
                _current = result;
                _info = result.Info;
                logger.LogInformation(
                    "Talep modeli eğitildi: {Rows} örnek, {Products} ürün, {Ms} ms. Test MAE {Mae} (basit ortalama {Baseline}), kapsama {Coverage}",
                    result.Info.TrainingRows, result.Info.ProductCount, result.Info.TrainingMs,
                    result.Info.TestMae, result.Info.BaselineMae, result.Info.DailyCoverage);
            }
            return _info;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Model eğitilemese de API çalışmaya devam eder; tahmin ekranı nedenini gösterir.
            logger.LogError(ex, "Talep modeli eğitilemedi.");
            _current = null;
            _info = NotTrained($"Model eğitilemedi: {ex.Message}");
            return _info;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<DemandForecastDto> ForecastAsync(int productId, decimal stock, CancellationToken ct = default)
    {
        if (_current is null) await TrainAsync(ct);
        var trained = _current;
        if (trained is null) return DemandTraining.Unavailable(_info.Reason ?? "Model eğitilemedi.", _info);

        using var scope = scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var lastDay = LastCompleteDay();
        var series = (await LoadSeriesAsync(db, productId, lastDay, ct)).FirstOrDefault();
        if (series is null)
            return DemandTraining.Unavailable("Bu ürünün henüz geçmiş bir günde hareketi yok.", trained.Info);

        var todayStart = TurkeyTime.TodayStartUtc;
        var todayOutSigned = await db.StockMovements
            .Where(m => m.ProductId == productId && m.Type == MovementType.Out && m.CreatedAtUtc >= todayStart)
            .SumAsync(m => (decimal?)m.Quantity, ct);
        var todayOut = -(todayOutSigned ?? 0); // çıkışlar negatif saklanır

        return DemandTraining.Forecast(trained, series, lastDay, stock, todayOut);
    }

    /// <summary>Son tam gün = dün (Türkiye). Bugünün yarım günü eğitime girmez.</summary>
    private static DateOnly LastCompleteDay() => DateOnly.FromDateTime(TurkeyTime.Now).AddDays(-1);

    /// <summary>
    /// Ürün başına günlük çıkış serisi. Seri, ürünün ilk hareket gününden başlar
    /// (ondan önceki günler "talep sıfır" değil "ürün yoktu" demektir; eğitime girmez).
    /// </summary>
    private static async Task<List<DailySeries>> LoadSeriesAsync(AppDbContext db, int? productId, DateOnly lastDay, CancellationToken ct)
    {
        var since = lastDay.AddDays(-MaxHistoryDays + 1);
        var sinceUtc = TimeZoneInfo.ConvertTimeToUtc(since.ToDateTime(TimeOnly.MinValue), TurkeyTime.Zone);

        var movements = db.StockMovements.AsNoTracking();
        if (productId is { } id) movements = movements.Where(m => m.ProductId == id);

        var firsts = await movements
            .GroupBy(m => m.ProductId)
            .Select(g => new { ProductId = g.Key, First = g.Min(m => m.CreatedAtUtc) })
            .ToListAsync(ct);

        var outs = await movements
            .Where(m => m.Type == MovementType.Out && m.CreatedAtUtc >= sinceUtc)
            .Select(m => new { m.ProductId, m.CreatedAtUtc, m.Quantity })
            .ToListAsync(ct);
        var outsByProduct = outs.ToLookup(m => m.ProductId);

        var result = new List<DailySeries>();
        foreach (var f in firsts)
        {
            var firstDay = DateOnly.FromDateTime(TurkeyTime.ToLocal(f.First));
            if (firstDay < since) firstDay = since;
            if (firstDay > lastDay) continue; // sadece bugün hareketi olan ürün

            var days = outsByProduct[f.ProductId]
                .Select(m => (DateOnly.FromDateTime(TurkeyTime.ToLocal(m.CreatedAtUtc)), (float)-m.Quantity));
            result.Add(DemandFeatures.BuildSeries(f.ProductId, firstDay, lastDay, days));
        }
        return result;
    }

    private static DemandModelInfoDto NotTrained(string reason) =>
        new(false, reason, DemandModel.Algorithm, null, 0, 0, 0, 0, DemandTraining.ConfidenceLevel, false,
            null, null, null, null, null);
}

/// <summary>Uygulama açılınca ve her <c>Demand:RetrainHours</c> saatte bir modeli yeniden eğitir.</summary>
public sealed class DemandModelTrainer(DemandForecaster forecaster, IConfiguration config)
    : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Yield(); // açılışı bekletme
        var hours = Math.Max(1, config.GetValue("Demand:RetrainHours", 6));
        using var timer = new PeriodicTimer(TimeSpan.FromHours(hours));
        try
        {
            do
            {
                await forecaster.TrainAsync(stoppingToken); // hataları kendisi yakalar ve loglar
            } while (await timer.WaitForNextTickAsync(stoppingToken));
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // kapanış
        }
    }
}
