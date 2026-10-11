using Microsoft.ML;
using StokTakip.Api.Services.Demand;

namespace StokTakip.Api.Tests;

/// <summary>Özellik mühendisliği (veri sızıntısı yok) ve gerçek ML.NET eğitimi, sentetik veriyle.</summary>
public class DemandForecastTests
{
    private static readonly DateOnly LastDay = new(2026, 10, 10); // cumartesi

    /// <summary>Pazartesi yoğun, pazar sıfır; hafif gürültü. Model bu deseni öğrenmeli.</summary>
    private static DailySeries Weekly(int productId, int days, float level, int seed)
    {
        double[] weekday = [1.25, 1.10, 1.00, 1.00, 1.15, 0.55, 0.0];
        var rng = new Random(seed);
        var first = LastDay.AddDays(-days + 1);
        var daily = new float[days];
        for (var i = 0; i < days; i++)
        {
            var w = weekday[DemandFeatures.DowIndex(first.AddDays(i).DayOfWeek)];
            daily[i] = (float)Math.Round(level * w * (0.8 + rng.NextDouble() * 0.4));
        }
        return new DailySeries(productId, first, daily);
    }

    [Fact]
    public void Features_use_only_data_up_to_origin()
    {
        var s = Weekly(1, 60, 10, 1);
        var origin = LastDay.AddDays(-20);
        var before = DemandFeatures.Build(s, origin, origin.AddDays(3), out var b1);

        // Origin'den sonraki günleri değiştirmek özellikleri etkilememeli.
        for (var i = s.IndexOf(origin) + 1; i < s.Daily.Length; i++) s.Daily[i] = 9999;
        var after = DemandFeatures.Build(s, origin, origin.AddDays(3), out var b2);

        Assert.Equal(before, after);
        Assert.Equal(b1, b2);
    }

    [Fact]
    public void Features_encode_weekday_and_levels()
    {
        var first = new DateOnly(2026, 9, 1);
        var s = new DailySeries(1, first, Enumerable.Repeat(2f, 40).ToArray());
        var origin = first.AddDays(35);
        var monday = new DateOnly(2026, 10, 12);

        var f = DemandFeatures.Build(s, origin, monday, out var baseline);

        Assert.Equal(1f, f[0]);                           // Pazartesi
        Assert.Equal(1f, f.Take(7).Sum());                 // tek gün işaretli
        Assert.Equal(MathF.Log(3), f[7], 5);               // log(1 + 2)
        Assert.Equal(MathF.Log(3), f[8], 5);
        Assert.Equal(0f, f[10]);                           // hiç sıfır gün yok
        Assert.Equal(2f, baseline);
    }

    [Fact]
    public void Training_examples_never_look_past_cutoff()
    {
        var s = Weekly(1, 90, 10, 2);
        var cutoff = LastDay.AddDays(-14);

        var examples = DemandFeatures.TrainingExamples([s], cutoff);

        Assert.NotEmpty(examples);
        Assert.All(examples, e =>
        {
            Assert.True(e.Target <= cutoff);
            Assert.True(e.Origin < e.Target);
            Assert.True(e.Target.DayNumber - e.Origin.DayNumber <= DemandFeatures.Horizon);
        });
    }

    [Fact]
    public void Quantile_matches_numpy_linear_interpolation()
    {
        Assert.Equal(3.7, DemandFeatures.Quantile([1, 2, 3, 4], 0.9), 10);
        Assert.Equal(2.5, DemandFeatures.Quantile([4, 1, 3, 2], 0.5), 10);
    }

    [Fact]
    public void Too_little_history_is_reported_not_trained()
    {
        var (result, reason) = DemandTraining.Run(new MLContext(seed: 1), [Weekly(1, 30, 5, 1)], LastDay);

        Assert.Null(result);
        Assert.Contains("yeterli geçmiş yok", reason);
    }

    [Fact]
    public void Model_learns_weekly_pattern_and_beats_flat_average()
    {
        var series = Enumerable.Range(1, 8).Select(i => Weekly(i, 120, 5 + i * 4, i)).ToList();

        var (trained, reason) = DemandTraining.Run(new MLContext(seed: 1), series, LastDay);

        Assert.Null(reason);
        Assert.NotNull(trained);
        var info = trained!.Info;
        Assert.True(info.Calibrated);
        Assert.True(info.TestMae < info.BaselineMae, $"Model {info.TestMae} / basit ortalama {info.BaselineMae}");
        Assert.InRange(info.DailyCoverage!.Value, 0.6, 1.0);

        var forecast = DemandTraining.Forecast(trained, series[3], LastDay, stock: 10_000, todayOut: 0);
        Assert.True(forecast.Available);
        Assert.Equal(DemandFeatures.Horizon, forecast.Forecast.Count);
        Assert.Equal(LastDay.AddDays(1), forecast.Forecast[0].Date);
        Assert.All(forecast.Forecast, p => Assert.True(p.Lower <= p.Forecast && p.Forecast <= p.Upper));

        var sunday = forecast.Forecast.First(p => p.Date.DayOfWeek == DayOfWeek.Sunday).Forecast;
        var monday = forecast.Forecast.First(p => p.Date.DayOfWeek == DayOfWeek.Monday).Forecast;
        Assert.True(sunday < monday * 0.2m, $"Pazar {sunday}, pazartesi {monday}");
    }

    [Fact]
    public void Forecast_finds_stockout_day_from_cumulative_demand()
    {
        var series = Enumerable.Range(1, 8).Select(i => Weekly(i, 120, 10, i)).ToList();
        var (trained, _) = DemandTraining.Run(new MLContext(seed: 1), series, LastDay);

        var low = DemandTraining.Forecast(trained!, series[0], LastDay, stock: 15, todayOut: 0);
        var high = DemandTraining.Forecast(trained!, series[0], LastDay, stock: 100_000, todayOut: 0);

        Assert.NotNull(low.StockoutDate);
        Assert.True(low.StockoutDate <= LastDay.AddDays(4));
        Assert.Null(high.StockoutDate);
    }
}
