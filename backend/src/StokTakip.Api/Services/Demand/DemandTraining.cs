using System.Diagnostics;
using Microsoft.ML;
using StokTakip.Api.Contracts;
using static StokTakip.Api.Services.Demand.DemandFeatures;

namespace StokTakip.Api.Services.Demand;

/// <summary>Eğitilmiş model + tahmin aralığı genişlikleri + ölçülen başarı.</summary>
public sealed record TrainedDemandModel(DemandModel Model, double DayQ, double TotalQ, DemandModelInfoDto Info);

/// <summary>
/// Eğitim ve tahmin akışı. Veritabanından bağımsız; seriler verilir, sonuç döner (birim testlerle sınanır).
///
/// Zamana göre üç adım (veri sızıntısı yok, her adım sadece geçmişle eğitilir):
/// 1. Kalibrasyon: [.. son-28] ile eğit, [son-27 .. son-14] tahmin et → %90 tahmin aralığının genişliği
///    (split conformal: gerçek hataların %90'ını kapsayan ölçekli hata eşiği).
/// 2. Test: [.. son-14] ile eğit, [son-13 .. son] tahmin et → model hatası, basit ortalamanın hatası ve
///    aralığın kalibrasyonda görülmemiş veride gerçek kapsama oranı. Ekranda dürüstçe gösterilir.
/// 3. Son model: tüm veriyle eğit, bugünden itibaren 14 gün tahmin et.
/// </summary>
public static class DemandTraining
{
    public const double ConfidenceLevel = 0.90;

    /// <summary>Bundan az eğitim örneğiyle model eğitilmez.</summary>
    public const int MinTrainingRows = 300;

    /// <summary>Kalibrasyon verisi yoksa Poisson varsayımı: %90 için z ≈ 1,645.</summary>
    public const double FallbackQ = 1.645;

    public static (TrainedDemandModel? Result, string? Reason) Run(
        MLContext ml, IReadOnlyList<DailySeries> series, DateOnly lastDay, int maxRows = 300_000)
    {
        var sw = Stopwatch.StartNew();
        var step = OriginStep(series, maxRows);
        var all = TrainingExamples(series, lastDay, step);
        if (all.Count < MinTrainingRows)
            return (null, $"ML modeli için yeterli geçmiş yok ({all.Count} örnek, en az {MinTrainingRows}). " +
                          "Ürünlerin en az 6-8 haftalık çıkış geçmişi olmalı.");

        // 1) Kalibrasyon
        double dayQ = FallbackQ, totalQ = FallbackQ;
        var calibrated = false;
        var (calPred, calEval) = Backtest(ml, series, lastDay.AddDays(-2 * Horizon), step);
        if (calPred is not null)
        {
            dayQ = Quantile(calEval.Select((e, i) => ScaledError(e.Label, calPred[i])), ConfidenceLevel);
            var totals = ProductTotals(calEval, calPred).Select(t => t.ScaledError).ToList();
            // 14 günlük toplamın hatası günlük hataların toplamından farklı davranır (hatalar birbirine bağlı);
            // yeterli ürün varsa ayrıca kalibre edilir.
            totalQ = totals.Count >= 5 ? Quantile(totals, ConfidenceLevel) : dayQ;
            calibrated = true;
        }

        // 2) Test
        double? mae = null, baselineMae = null, coverage = null;
        int? hits = null, count = null;
        var (testPred, testEval) = Backtest(ml, series, lastDay.AddDays(-Horizon), step);
        if (testPred is not null)
        {
            mae = testEval.Select((e, i) => (double)Math.Abs(e.Label - testPred[i])).Average();
            baselineMae = testEval.Average(e => (double)Math.Abs(e.Label - e.Baseline));
            coverage = testEval.Select((e, i) => ScaledError(e.Label, testPred[i]) <= dayQ ? 1.0 : 0.0).Average();
            var totals = ProductTotals(testEval, testPred);
            hits = totals.Count(t => t.ScaledError <= totalQ);
            count = totals.Count;
        }

        // 3) Son model
        var model = DemandModel.Train(ml, all);
        sw.Stop();

        var info = new DemandModelInfoDto(
            Trained: true,
            Reason: null,
            Algorithm: DemandModel.Algorithm,
            TrainedAtUtc: DateTime.UtcNow,
            TrainingMs: sw.ElapsedMilliseconds,
            TrainingRows: all.Count,
            ProductCount: all.Select(e => e.ProductId).Distinct().Count(),
            HistoryDays: series.Max(s => s.Daily.Length),
            ConfidenceLevel: ConfidenceLevel,
            Calibrated: calibrated,
            TestMae: Round(mae),
            BaselineMae: Round(baselineMae),
            DailyCoverage: Round(coverage),
            TotalHits: hits,
            TotalCount: count);

        return (new TrainedDemandModel(model, dayQ, totalQ, info), null);
    }

    /// <summary>Son tam günden (<paramref name="lastDay"/>) sonraki 14 gün: bugünden başlar.</summary>
    /// <param name="todayOut">Bugün şimdiye kadarki çıkış; stok bunu zaten düşmüş olduğundan tükenme hesabında bugünün tahmininden çıkarılır.</param>
    public static DemandForecastDto Forecast(
        TrainedDemandModel trained, DailySeries series, DateOnly lastDay, decimal stock, decimal todayOut)
    {
        var history = History(series, lastDay);
        if (!HasWindow(series, lastDay))
        {
            var days = Math.Max(0, series.IndexOf(lastDay) + 1);
            return Unavailable(
                $"Bu ürünün {days} günlük geçmişi var; ML tahmini için en az {Lookback} gün gerekli.",
                trained.Info, history);
        }

        var features = new List<float[]>();
        for (var h = 1; h <= Horizon; h++)
            features.Add(Build(series, lastDay, lastDay.AddDays(h), out _));
        var pred = trained.Model.Predict(features);

        var points = new List<DemandForecastDayDto>();
        for (var i = 0; i < pred.Length; i++)
        {
            var half = trained.DayQ * Math.Sqrt(pred[i] + 1);
            points.Add(new DemandForecastDayDto(
                lastDay.AddDays(i + 1),
                Dec(pred[i]),
                Dec(Math.Max(0, pred[i] - half)),
                Dec(pred[i] + half)));
        }

        var total = pred.Sum(p => (double)p);
        var totalHalf = trained.TotalQ * Math.Sqrt(pred.Sum(p => p + 1.0));

        // Tükenme: kümülatif beklenen çıkış mevcut stoğu ne zaman geçer?
        DateOnly? stockout = null;
        if (stock <= 0) stockout = lastDay.AddDays(1);
        else
        {
            double cumulative = 0;
            for (var i = 0; i < pred.Length; i++)
            {
                cumulative += i == 0 ? Math.Max(0, pred[0] - (double)todayOut) : pred[i];
                if (cumulative > (double)stock)
                {
                    stockout = lastDay.AddDays(i + 1);
                    break;
                }
            }
        }

        return new DemandForecastDto(
            true, null, history, points,
            Dec(total), Dec(Math.Max(0, total - totalHalf)), Dec(total + totalHalf),
            stockout, trained.Info);
    }

    public static DemandForecastDto Unavailable(string reason, DemandModelInfoDto info, List<DemandDayDto>? history = null) =>
        new(false, reason, history ?? [], [], 0, 0, 0, null, info);

    /// <summary>Grafik için son 28 tam gün (ürünün ilk gününden öncesi yok).</summary>
    private static List<DemandDayDto> History(DailySeries s, DateOnly lastDay)
    {
        var list = new List<DemandDayDto>();
        for (var d = lastDay.AddDays(-Lookback + 1); d <= lastDay; d = d.AddDays(1))
        {
            var i = s.IndexOf(d);
            if (i >= 0 && i < s.Daily.Length) list.Add(new DemandDayDto(d, Dec(s.Daily[i])));
        }
        return list;
    }

    private static (float[]? Pred, List<DemandExample> Eval) Backtest(
        MLContext ml, IReadOnlyList<DailySeries> series, DateOnly origin, int step)
    {
        var train = TrainingExamples(series, origin, step);
        var eval = EvaluationExamples(series, origin);
        if (train.Count < MinTrainingRows || eval.Count == 0) return (null, eval);
        var model = DemandModel.Train(ml, train);
        return (model.Predict(eval.Select(e => e.Features).ToList()), eval);
    }

    /// <summary>Ürün başına 14 günlük toplam hata, √(Σtahmin + 14) ile ölçeklenmiş.</summary>
    private static List<(int ProductId, double ScaledError)> ProductTotals(List<DemandExample> eval, float[] pred) =>
        eval.Select((e, i) => (e.ProductId, Actual: (double)e.Label, Pred: (double)pred[i]))
            .GroupBy(x => x.ProductId)
            .Select(g => (g.Key, Math.Abs(g.Sum(x => x.Actual) - g.Sum(x => x.Pred)) / Math.Sqrt(g.Sum(x => x.Pred + 1))))
            .ToList();

    private static double? Round(double? v) => v is null ? null : Math.Round(v.Value, 3);
    private static decimal Dec(double v) => Math.Round((decimal)v, 1);
}
