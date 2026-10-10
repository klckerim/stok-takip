using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace StokTakip.Api.Data;

/// <summary>
/// Sadece "dotnet ef migrations add ..." komutu için. Uygulamayı çalıştırmadan DbContext oluşturur.
/// Migration üretmek veritabanına bağlanmayı gerektirmez; bağlantı cümlesi sadece biçim için var.
/// </summary>
public class AppDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer("Server=localhost,1433;Database=StokTakip;User Id=sa;Password=Guclu_Sifre_123;TrustServerCertificate=True")
            .Options;
        return new AppDbContext(options);
    }
}
