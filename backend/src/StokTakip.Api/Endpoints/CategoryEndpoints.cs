using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Contracts;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;

namespace StokTakip.Api.Endpoints;

public static class CategoryEndpoints
{
    public static void MapCategoryEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/categories").WithTags("Categories").RequireAuthorization();
        group.MapGet("/", List);
        group.MapPost("/", Create).RequireAuthorization(p => p.RequireRole(Roles.Admin));
        group.MapDelete("/{id:int}", Delete).RequireAuthorization(p => p.RequireRole(Roles.Admin));
    }

    private static async Task<IResult> List(AppDbContext db)
    {
        var items = await db.Categories.AsNoTracking()
            .OrderBy(c => c.Name)
            .Select(c => new CategoryDto(c.Id, c.Name, c.Products.Count))
            .ToListAsync();
        return Results.Ok(items);
    }

    private static async Task<IResult> Create(CreateCategoryRequest req, AppDbContext db)
    {
        var name = req.Name?.Trim() ?? "";
        if (name.Length == 0)
            return Results.ValidationProblem(new Dictionary<string, string[]> { ["name"] = ["Kategori adı zorunlu."] });
        if (name.Length > 100)
            return Results.ValidationProblem(new Dictionary<string, string[]> { ["name"] = ["En fazla 100 karakter."] });
        if (await db.Categories.AnyAsync(c => c.Name == name))
            return Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Bu kategori zaten var.");

        var category = new Category { Name = name };
        db.Categories.Add(category);
        await db.SaveChangesAsync();
        return Results.Created($"/api/categories/{category.Id}", new CategoryDto(category.Id, category.Name, 0));
    }

    /// <summary>Kategori silinir; içindeki ürünler kategorisiz kalır.</summary>
    private static async Task<IResult> Delete(int id, AppDbContext db)
    {
        var category = await db.Categories.FindAsync(id);
        if (category is null)
            return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Kategori bulunamadı.");

        db.Categories.Remove(category);
        await db.SaveChangesAsync();
        return Results.NoContent();
    }
}
