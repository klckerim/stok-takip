using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Contracts;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;

namespace StokTakip.Api.Endpoints;

public static class ProductEndpoints
{
    public static void MapProductEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/products").WithTags("Products").RequireAuthorization();

        group.MapGet("/", List);
        group.MapGet("/barcode/{barcode}", GetByBarcode);
        group.MapGet("/{id:int}/movements", GetMovements);
        group.MapPost("/", Create).RequireAuthorization(p => p.RequireRole(Roles.Admin));
    }

    /// <summary>Ürünler ve anlık stokları. ?search= ile ad veya barkodda arar.</summary>
    private static async Task<IResult> List(AppDbContext db, string? search)
    {
        var query = db.Products.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            query = query.Where(p => p.Name.Contains(s) || p.Barcode.Contains(s));
        }

        var items = await query
            .OrderBy(p => p.Name)
            .Select(p => new ProductDto(p.Id, p.Barcode, p.Name, p.Unit, p.Movements.Sum(m => m.Quantity)))
            .Take(200)
            .ToListAsync();

        return Results.Ok(items);
    }

    /// <summary>Mobilde barkod okutulunca çağrılır.</summary>
    private static async Task<IResult> GetByBarcode(string barcode, AppDbContext db)
    {
        var product = await db.Products.AsNoTracking()
            .Where(p => p.Barcode == barcode.Trim())
            .Select(p => new ProductDto(p.Id, p.Barcode, p.Name, p.Unit, p.Movements.Sum(m => m.Quantity)))
            .SingleOrDefaultAsync();

        return product is null
            ? Results.Problem(statusCode: StatusCodes.Status404NotFound, title: $"'{barcode}' barkodlu ürün bulunamadı.")
            : Results.Ok(product);
    }

    private static async Task<IResult> GetMovements(int id, AppDbContext db, int take = 20)
    {
        if (!await db.Products.AnyAsync(p => p.Id == id))
            return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Ürün bulunamadı.");

        var items = await db.StockMovements.AsNoTracking()
            .Where(m => m.ProductId == id)
            .OrderByDescending(m => m.CreatedAtUtc)
            .Take(Math.Clamp(take, 1, 100))
            .Select(m => new MovementDto(m.Id, m.Type, m.Quantity, m.CountedQuantity, m.Note, m.User.UserName, m.CreatedAtUtc))
            .ToListAsync();

        return Results.Ok(items);
    }

    private static async Task<IResult> Create(CreateProductRequest req, AppDbContext db)
    {
        var errors = new Dictionary<string, string[]>();
        if (string.IsNullOrWhiteSpace(req.Barcode)) errors["barcode"] = ["Barkod zorunlu."];
        if (string.IsNullOrWhiteSpace(req.Name)) errors["name"] = ["Ürün adı zorunlu."];
        if (string.IsNullOrWhiteSpace(req.Unit)) errors["unit"] = ["Birim zorunlu."];
        if (errors.Count > 0) return Results.ValidationProblem(errors);

        var barcode = req.Barcode.Trim();
        if (await db.Products.AnyAsync(p => p.Barcode == barcode))
            return Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Bu barkod zaten kayıtlı.");

        var product = new Product { Barcode = barcode, Name = req.Name.Trim(), Unit = req.Unit.Trim() };
        db.Products.Add(product);
        await db.SaveChangesAsync();

        return Results.Created($"/api/products/{product.Id}",
            new ProductDto(product.Id, product.Barcode, product.Name, product.Unit, 0));
    }
}
