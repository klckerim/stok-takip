using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Domain;

namespace StokTakip.Api.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<StockMovement> StockMovements => Set<StockMovement>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>(e =>
        {
            e.Property(x => x.UserName).HasMaxLength(50);
            e.Property(x => x.FullName).HasMaxLength(100);
            e.Property(x => x.Role).HasMaxLength(20);
            e.HasIndex(x => x.UserName).IsUnique();
        });

        b.Entity<Product>(e =>
        {
            e.Property(x => x.Barcode).HasMaxLength(64);
            e.Property(x => x.Name).HasMaxLength(200);
            e.Property(x => x.Unit).HasMaxLength(20);
            e.Property(x => x.MinStock).HasPrecision(18, 3);
            e.Property(x => x.CreatedAtUtc).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasIndex(x => x.Barcode).IsUnique();
        });

        b.Entity<StockMovement>(e =>
        {
            e.Property(x => x.Quantity).HasPrecision(18, 3);
            e.Property(x => x.CountedQuantity).HasPrecision(18, 3);
            e.Property(x => x.Type).HasConversion<byte>();
            e.Property(x => x.Note).HasMaxLength(500);
            // SQL Server'dan okunan tarih "Unspecified" gelir; UTC olduğunu belirt ki JSON'da "Z" ile gitsin.
            e.Property(x => x.CreatedAtUtc).HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
            e.HasIndex(x => new { x.ProductId, x.CreatedAtUtc });
            e.HasIndex(x => x.ClientRequestId)
                .IsUnique()
                .HasFilter("[ClientRequestId] IS NOT NULL");
            e.HasOne(x => x.Product).WithMany(p => p.Movements).HasForeignKey(x => x.ProductId);
            e.HasOne(x => x.User).WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        });
    }
}
