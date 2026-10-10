using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using StokTakip.Api.Contracts;
using StokTakip.Api.Data;
using StokTakip.Api.Domain;
using StokTakip.Api.Services;

namespace StokTakip.Api.Endpoints;

public static class AuthEndpoints
{
    public static void MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/auth/login", Login)
            .WithTags("Auth")
            .AllowAnonymous();
    }

    private static async Task<IResult> Login(LoginRequest req, AppDbContext db, TokenService tokens)
    {
        var user = await db.Users.SingleOrDefaultAsync(u => u.UserName == req.UserName.Trim());
        if (user is null)
            return InvalidCredentials();

        var result = new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash, req.Password);
        if (result == PasswordVerificationResult.Failed)
            return InvalidCredentials();

        var (token, expires) = tokens.Create(user);
        return Results.Ok(new LoginResponse(token, user.FullName, user.Role, expires));
    }

    private static IResult InvalidCredentials() =>
        Results.Problem(statusCode: StatusCodes.Status401Unauthorized, title: "Kullanıcı adı veya şifre hatalı.");
}
