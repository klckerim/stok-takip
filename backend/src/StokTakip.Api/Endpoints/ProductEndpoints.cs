using System.Linq.Expressions;
using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Contracts;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;
using StokTakip.Api.Services;

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
        group.MapPut("/{id:int}", Update).RequireAuthorization(p => p.RequireRole(Roles.Admin));
    }

    /// <summary>Ürünü anlık stok ve kategori adıyla DTO'ya çevirir (SQL'e çevrilir).</summary>
    internal static readonly Expression<Func<Product, ProductDto>> ToDto = p => new ProductDto(
        p.Id, p.Barcode, p.Name, p.Unit, p.Movements.Sum(m => m.Quantity), p.MinStock,
        p.CategoryId, p.Category != null ? p.Category.Name : null);

    /// <summary>
    /// Ürünler ve anlık stokları.
    /// ?search= ad veya barkodda arar, ?criticalOnly=true sadece kritikler, ?categoryId= kategoriye göre.
    /// </summary>
    private static async Task<IResult> List(AppDbContext db, string? search, int? categoryId, bool criticalOnly = false)
    {
        var query = db.Products.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            query = query.Where(p => p.Name.Contains(s) || p.Barcode.Contains(s));
        }
        if (categoryId is { } cid)
        {
            query = query.Where(p => p.CategoryId == cid);
        }
        if (criticalOnly)
        {
            query = query.Where(p => p.MinStock > 0 && p.Movements.Sum(m => m.Quantity) <= p.MinStock);
        }

        var items = await query
            .OrderBy(p => p.Name)
            .Select(ToDto)
            .Take(200)
            .ToListAsync();

        return Results.Ok(items);
    }

    /// <summary>Mobilde barkod okutulunca çağrılır.</summary>
    private static async Task<IResult> GetByBarcode(string barcode, AppDbContext db)
    {
        var product = await db.Products.AsNoTracking()
            .Where(p => p.Barcode == barcode.Trim())
            .Select(ToDto)
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
            .ThenByDescending(m => m.Id)
            .Take(Math.Clamp(take, 1, 100))
            .Select(m => new MovementDto(m.Id, m.Type, m.Quantity, m.CountedQuantity, m.Note, m.User.UserName, m.CreatedAtUtc))
            .ToListAsync();

        return Results.Ok(items);
    }

    /// <summary>Yeni ürün. InitialStock verilirse "Açılış stoğu" giriş hareketi de yazılır.</summary>
    private static async Task<IResult> Create(CreateProductRequest req, AppDbContext db, ClaimsPrincipal user)
    {
        var errors = Validate(req.Name, req.Unit, req.MinStock);
        if (string.IsNullOrWhiteSpace(req.Barcode)) errors["barcode"] = ["Barkod zorunlu."];
        if (req.InitialStock < 0) errors["initialStock"] = ["Açılış stoğu negatif olamaz."];
        if (req.CategoryId is { } cid && !await db.Categories.AnyAsync(c => c.Id == cid))
            errors["categoryId"] = ["Kategori bulunamadı."];
        if (errors.Count > 0) return Results.ValidationProblem(errors);

        var barcode = req.Barcode.Trim();
        if (await db.Products.AnyAsync(p => p.Barcode == barcode))
            return Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Bu barkod zaten kayıtlı.");

        var product = new Product
        {
            Barcode = barcode,
            Name = req.Name.Trim(),
            Unit = req.Unit.Trim(),
            MinStock = req.MinStock,
            CategoryId = req.CategoryId
        };
        if (req.InitialStock > 0)
        {
            product.Movements.Add(new StockMovement
            {
                Type = MovementType.In,
                Quantity = req.InitialStock,
                Note = "Açılış stoğu",
                UserId = user.UserId()
            });
        }

        db.Products.Add(product);
        await db.SaveChangesAsync();

        var created = await db.Products.AsNoTracking().Where(p => p.Id == product.Id).Select(ToDto).SingleAsync();
        return Results.Created($"/api/products/{product.Id}", created);
    }

    /// <summary>Ad, birim, kritik seviye ve kategori güncellenir. Barkod değişmez.</summary>
    private static async Task<IResult> Update(int id, UpdateProductRequest req, AppDbContext db)
    {
        var errors = Validate(req.Name, req.Unit, req.MinStock);
        if (req.CategoryId is { } cid && !await db.Categories.AnyAsync(c => c.Id == cid))
            errors["categoryId"] = ["Kategori bulunamadı."];
        if (errors.Count > 0) return Results.ValidationProblem(errors);

        var product = await db.Products.FindAsync(id);
        if (product is null)
            return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Ürün bulunamadı.");

        product.Name = req.Name.Trim();
        product.Unit = req.Unit.Trim();
        product.MinStock = req.MinStock;
        product.CategoryId = req.CategoryId;
        await db.SaveChangesAsync();

        var updated = await db.Products.AsNoTracking().Where(p => p.Id == id).Select(ToDto).SingleAsync();
        return Results.Ok(updated);
    }

    private static Dictionary<string, string[]> Validate(string name, string unit, decimal minStock)
    {
        var errors = new Dictionary<string, string[]>();
        if (string.IsNullOrWhiteSpace(name)) errors["name"] = ["Ürün adı zorunlu."];
        if (string.IsNullOrWhiteSpace(unit)) errors["unit"] = ["Birim zorunlu."];
        if (minStock < 0) errors["minStock"] = ["Kritik seviye negatif olamaz."];
        return errors;
    }
}
