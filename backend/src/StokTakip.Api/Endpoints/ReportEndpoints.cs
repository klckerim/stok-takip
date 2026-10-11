using ClosedXML.Excel;
using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;
using StokTakip.Api.Services;

namespace StokTakip.Api.Endpoints;

/// <summary>Excel (.xlsx) raporları. Mobilde indirilip paylaşılır (WhatsApp, e-posta, Dosyalar).</summary>
public static class ReportEndpoints
{
    private const string XlsxContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    public static void MapReportEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/reports").WithTags("Reports").RequireAuthorization();
        group.MapGet("/stock.xlsx", StockReport);
        group.MapGet("/movements.xlsx", MovementReport);
    }

    /// <summary>Tüm ürünlerin anlık stoğu; kritik olanlar kırmızı.</summary>
    private static async Task<IResult> StockReport(AppDbContext db)
    {
        var rows = await db.Products.AsNoTracking()
            .OrderBy(p => p.Name)
            .Select(p => new
            {
                p.Barcode,
                p.Name,
                Category = p.Category != null ? p.Category.Name : "",
                p.Unit,
                Stock = p.Movements.Sum(m => m.Quantity),
                p.MinStock
            })
            .ToListAsync();

        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Stok");
        WriteHeader(ws, "Barkod", "Ürün", "Kategori", "Birim", "Stok", "Kritik seviye", "Durum");

        var r = 2;
        foreach (var x in rows)
        {
            var critical = x.MinStock > 0 && x.Stock <= x.MinStock;
            ws.Cell(r, 1).Value = x.Barcode;
            ws.Cell(r, 2).Value = x.Name;
            ws.Cell(r, 3).Value = x.Category;
            ws.Cell(r, 4).Value = x.Unit;
            ws.Cell(r, 5).Value = (double)x.Stock;
            ws.Cell(r, 6).Value = (double)x.MinStock;
            ws.Cell(r, 7).Value = critical ? "KRİTİK" : "";
            if (critical)
                ws.Range(r, 1, r, 7).Style.Fill.BackgroundColor = XLColor.FromHtml("#FDE2E1");
            r++;
        }

        ws.Range(2, 5, Math.Max(r - 1, 2), 6).Style.NumberFormat.Format = "#,##0.###";
        SetWidths(ws, 16, 36, 16, 8, 12, 14, 10);
        return File(wb, $"stok-raporu-{LocalNow():yyyy-MM-dd}.xlsx");
    }

    /// <summary>Son N günün hareketleri (varsayılan 30, en fazla 365).</summary>
    private static async Task<IResult> MovementReport(AppDbContext db, int days = 30)
    {
        days = Math.Clamp(days, 1, 365);
        var since = DateTime.UtcNow.AddDays(-days);

        var rows = await db.StockMovements.AsNoTracking()
            .Where(m => m.CreatedAtUtc >= since)
            .OrderByDescending(m => m.CreatedAtUtc)
            .Select(m => new
            {
                m.CreatedAtUtc,
                m.Product.Barcode,
                ProductName = m.Product.Name,
                m.Product.Unit,
                m.Type,
                m.Quantity,
                m.CountedQuantity,
                m.User.UserName,
                m.Note
            })
            .ToListAsync();

        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Hareketler");
        WriteHeader(ws, "Tarih", "Barkod", "Ürün", "Birim", "Hareket", "Miktar", "Sayılan", "Kullanıcı", "Not");

        var r = 2;
        foreach (var x in rows)
        {
            ws.Cell(r, 1).Value = ToLocal(x.CreatedAtUtc);
            ws.Cell(r, 2).Value = x.Barcode;
            ws.Cell(r, 3).Value = x.ProductName;
            ws.Cell(r, 4).Value = x.Unit;
            ws.Cell(r, 5).Value = x.Type switch
            {
                MovementType.In => "Giriş",
                MovementType.Out => "Çıkış",
                _ => "Sayım"
            };
            ws.Cell(r, 6).Value = (double)x.Quantity;
            if (x.CountedQuantity is { } counted) ws.Cell(r, 7).Value = (double)counted;
            ws.Cell(r, 8).Value = x.UserName;
            ws.Cell(r, 9).Value = x.Note ?? "";
            r++;
        }

        ws.Range(2, 1, Math.Max(r - 1, 2), 1).Style.NumberFormat.Format = "dd.mm.yyyy hh:mm";
        ws.Range(2, 6, Math.Max(r - 1, 2), 7).Style.NumberFormat.Format = "#,##0.###";
        SetWidths(ws, 17, 16, 32, 8, 10, 10, 10, 12, 30);
        return File(wb, $"hareketler-son-{days}-gun-{LocalNow():yyyy-MM-dd}.xlsx");
    }

    private static void WriteHeader(IXLWorksheet ws, params string[] titles)
    {
        for (var i = 0; i < titles.Length; i++)
            ws.Cell(1, i + 1).Value = titles[i];

        var header = ws.Range(1, 1, 1, titles.Length);
        header.Style.Font.Bold = true;
        header.Style.Fill.BackgroundColor = XLColor.FromHtml("#E7F0EE");
        ws.SheetView.FreezeRows(1);
        ws.RangeUsed()?.SetAutoFilter();
    }

    // AdjustToContents sunucuda font gerektirdiği için genişlikler elle veriliyor.
    private static void SetWidths(IXLWorksheet ws, params double[] widths)
    {
        for (var i = 0; i < widths.Length; i++)
            ws.Column(i + 1).Width = widths[i];
    }

    private static IResult File(XLWorkbook wb, string fileName)
    {
        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return Results.File(ms.ToArray(), XlsxContentType, fileName);
    }

    private static DateTime ToLocal(DateTime utc) => TurkeyTime.ToLocal(utc);

    private static DateTime LocalNow() => TurkeyTime.Now;
}
