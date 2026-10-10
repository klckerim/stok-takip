using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using StokTakip.Api.Domain;

namespace StokTakip.Api.Services;

public class JwtOptions
{
    public string Issuer { get; set; } = "StokTakip";
    public string Audience { get; set; } = "StokTakip.Mobile";

    /// <summary>HS256 için en az 32 karakter. Canlıda ortam değişkeninden verilmeli.</summary>
    public string Key { get; set; } = "";

    public int ExpiryHours { get; set; } = 12;

    public SymmetricSecurityKey SigningKey() => new(Encoding.UTF8.GetBytes(Key));
}

public class TokenService(JwtOptions options)
{
    public (string Token, DateTime ExpiresAtUtc) Create(User user)
    {
        var expires = DateTime.UtcNow.AddHours(options.ExpiryHours);
        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = options.Issuer,
            Audience = options.Audience,
            Expires = expires,
            Subject = new ClaimsIdentity(
            [
                new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
                new Claim(ClaimTypes.Name, user.UserName),
                new Claim(ClaimTypes.Role, user.Role),
            ]),
            SigningCredentials = new SigningCredentials(options.SigningKey(), SecurityAlgorithms.HmacSha256)
        };

        return (new JsonWebTokenHandler().CreateToken(descriptor), expires);
    }
}

public static class ClaimsPrincipalExtensions
{
    public static int UserId(this ClaimsPrincipal user) =>
        int.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier)
                  ?? throw new InvalidOperationException("Token içinde kullanıcı id yok."));
}
