using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Domain;

namespace StokTakip.Api.Data;

public static class DbInitializer
{
    /// <summary>
    /// Bekleyen migration'ları uygular ve boş veritabanına demo verisini yükler.
    /// SQL Server container'ı API'den geç ayağa kalkabildiği için birkaç kez dener.
    /// Projede henüz migration yoksa (ilk kurulum) şemayı EnsureCreated ile oluşturur.
    /// </summary>
    public static async Task InitializeAsync(IServiceProvider services, ILogger logger)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        for (var attempt = 1; ; attempt++)
        {
            try
            {
                if (db.Database.GetMigrations().Any())
                    await db.Database.MigrateAsync();
                else
                    await db.Database.EnsureCreatedAsync();
                break;
            }
            catch (Exception ex) when (attempt < 10)
            {
                logger.LogWarning("Veritabanına bağlanılamadı ({Attempt}/10): {Message}", attempt, ex.Message);
                await Task.Delay(TimeSpan.FromSeconds(3));
            }
        }

        if (await db.Users.AnyAsync()) return;

        var hasher = new PasswordHasher<User>();
        var admin = new User { UserName = "admin", FullName = "Depo Yöneticisi", Role = Roles.Admin };
        admin.PasswordHash = hasher.HashPassword(admin, "Admin123!");
        var depo = new User { UserName = "depo", FullName = "Depo Personeli", Role = Roles.Depo };
        depo.PasswordHash = hasher.HashPassword(depo, "Depo123!");
        db.Users.AddRange(admin, depo);

        // Demo ürünler (barkodlar uydurma, test için).
        // Palet bilerek kritik seviyenin altında başlıyor (demo için).
        var products = new (string Barcode, string Name, string Unit, decimal Stock, decimal MinStock)[]
        {
            ("8690000000011", "Polyester İplik 150 Denye", "Kg", 250, 100),
            ("8690000000028", "Karton Koli 60x40x40", "Adet", 1200, 300),
            ("8690000000035", "Streç Film 50 cm", "Rulo", 80, 20),
            ("8690000000042", "Makarna Ambalaj Filmi", "Kg", 430, 150),
            ("8690000000059", "Palet (Euro)", "Adet", 60, 80),
        };

        foreach (var p in products)
        {
            var product = new Product { Barcode = p.Barcode, Name = p.Name, Unit = p.Unit, MinStock = p.MinStock };
            product.Movements.Add(new StockMovement
            {
                Type = MovementType.In,
                Quantity = p.Stock,
                Note = "Açılış stoğu",
                User = admin
            });
            db.Products.Add(product);
        }

        await db.SaveChangesAsync();
        logger.LogInformation("Demo verisi yüklendi: 2 kullanıcı, {Count} ürün", products.Length);
    }
}
