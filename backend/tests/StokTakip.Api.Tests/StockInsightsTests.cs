using StokTakip.Api.Services;

namespace StokTakip.Api.Tests;

/// <summary>Tahmin ve anomali hesapları: veritabanı gerektirmeyen, hızlı birim testleri.</summary>
public class StockInsightsTests
{
    private static readonly DateTime Now = new(2026, 10, 11, 12, 0, 0, DateTimeKind.Utc);
    private static readonly InsightOptions Options = new();

    /// <summary>Son <paramref name="days"/> günün her birinde bir çıkış: 1 saat önce, 1 gün 1 saat önce, ...
    /// Hepsi pencerenin içinde kalır (en eskisi Now − (days−1) gün − 1 saat).</summary>
    private static List<OutPoint> DailyOuts(int days, decimal perDay) =>
        Enumerable.Range(0, days).Select(d => new OutPoint(Now.AddDays(-d).AddHours(-1), perDay)).ToList();

    [Fact]
    public void No_outs_means_no_forecast()
    {
        var f = StockInsights.Forecast(100, [], Now, Now.AddDays(-60), Options);

        Assert.Equal(0, f.AvgDailyOut);
        Assert.Null(f.DaysLeft);
        Assert.Equal(0, f.SuggestedMinStock);
    }

    [Fact]
    public void Daily_average_gives_days_left_and_suggested_min_stock()
    {
        var f = StockInsights.Forecast(100, DailyOuts(30, 2), Now, Now.AddDays(-90), Options);

        Assert.Equal(2, f.AvgDailyOut);       // 60 / 30 gün
        Assert.Equal(50, f.DaysLeft);         // 100 / 2
        Assert.Equal(20, f.SuggestedMinStock); // 2 × (7 tedarik + 3 emniyet)
        Assert.Equal(Now.AddDays(50), f.StockoutDateUtc);
    }

    [Fact]
    public void New_product_uses_shorter_window_so_average_is_not_diluted()
    {
        // Ürün 5 gün önce eklenmiş, 5 gündür günde 3 çıkıyor. 30 güne bölünseydi ortalama 0,5 çıkardı.
        var f = StockInsights.Forecast(30, DailyOuts(5, 3), Now, Now.AddDays(-5), Options);

        Assert.Equal(7, f.WindowDays);  // en az 7 gün
        Assert.Equal(15m / 7, f.AvgDailyOut, 3);
    }

    [Fact]
    public void Out_of_stock_product_has_zero_days_left()
    {
        var f = StockInsights.Forecast(0, DailyOuts(30, 1), Now, Now.AddDays(-60), Options);
        Assert.Equal(0, f.DaysLeft);
    }

    [Fact]
    public void Large_out_compared_to_history_is_flagged()
    {
        decimal[] history = [10, 12, 9, 11, 10, 10, 8];

        Assert.True(StockInsights.CheckOut(60, history, Options).IsAnomaly);
        Assert.False(StockInsights.CheckOut(14, history, Options).IsAnomaly);
    }

    [Fact]
    public void Out_check_needs_minimum_history()
    {
        decimal[] history = [10, 10, 10];
        Assert.False(StockInsights.CheckOut(500, history, Options).IsAnomaly);
    }

    [Fact]
    public void Identical_history_does_not_flag_small_deviation()
    {
        // Hep 10 çıkan üründe std = 0; 12 alarm olmamalı.
        decimal[] history = [10, 10, 10, 10, 10, 10];
        Assert.False(StockInsights.CheckOut(12, history, Options).IsAnomaly);
    }

    [Fact]
    public void Big_count_difference_is_flagged()
    {
        Assert.True(StockInsights.CheckCount(delta: -30, counted: 70, Options).IsAnomaly);  // 100'den 70'e: %30
        Assert.False(StockInsights.CheckCount(delta: -2, counted: 98, Options).IsAnomaly);  // %2
    }
}
