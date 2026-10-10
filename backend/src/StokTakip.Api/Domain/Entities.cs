namespace StokTakip.Api.Domain;

public static class Roles
{
    public const string Admin = "Admin";
    public const string Depo = "Depo";
}

public class User
{
    public int Id { get; set; }
    public required string UserName { get; set; }
    public required string FullName { get; set; }
    public string PasswordHash { get; set; } = "";
    public required string Role { get; set; }
}

public class Product
{
    public int Id { get; set; }
    public required string Barcode { get; set; }
    public required string Name { get; set; }
    public required string Unit { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    public List<StockMovement> Movements { get; set; } = [];
}

public enum MovementType
{
    In = 1,     // Depoya giriş
    Out = 2,    // Depodan çıkış
    Count = 3   // Sayım düzeltmesi
}

/// <summary>
/// Stok tablosu tutulmaz; anlık stok = hareketlerin toplamı (Quantity işaretlidir).
/// Böylece her değişikliğin kim tarafından, ne zaman yapıldığı kayıt altında kalır.
/// </summary>
public class StockMovement
{
    public long Id { get; set; }
    public int ProductId { get; set; }
    public Product Product { get; set; } = null!;
    public MovementType Type { get; set; }

    /// <summary>Stoka etkisi: giriş +, çıkış -, sayımda (sayılan - mevcut).</summary>
    public decimal Quantity { get; set; }

    /// <summary>Sadece sayım hareketinde: sayılan miktar.</summary>
    public decimal? CountedQuantity { get; set; }

    public string? Note { get; set; }
    public int UserId { get; set; }
    public User User { get; set; } = null!;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Mobil cihazın ürettiği benzersiz id. Aynı istek iki kez gelirse (zayıf Wi-Fi, tekrar deneme,
    /// ileride offline senkron) hareket iki kez yazılmaz.
    /// </summary>
    public Guid? ClientRequestId { get; set; }
}
