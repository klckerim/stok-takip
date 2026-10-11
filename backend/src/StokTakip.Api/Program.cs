using System.Security.Claims;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Scalar.AspNetCore;
using StokTakip.Api.Data;
using StokTakip.Api.Endpoints;
using StokTakip.Api.Services;
using StokTakip.Api.Services.Demand;

var builder = WebApplication.CreateBuilder(args);

// --- Ayarlar ---
var jwt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
if (jwt.Key.Length < 32)
    throw new InvalidOperationException("Jwt:Key en az 32 karakter olmalı (ortam değişkeni: Jwt__Key).");
builder.Services.AddSingleton(jwt);
builder.Services.AddSingleton<TokenService>();
builder.Services.AddSingleton(builder.Configuration.GetSection("Insights").Get<InsightOptions>() ?? new InsightOptions());

// --- ML.NET talep tahmini: model bellekte, açılışta ve periyodik olarak arka planda eğitilir ---
builder.Services.AddSingleton<DemandForecaster>();
builder.Services.AddHostedService<DemandModelTrainer>();

// --- Veritabanı ---
builder.Services.AddDbContext<AppDbContext>((sp, options) =>
    options.UseSqlServer(sp.GetRequiredService<IConfiguration>().GetConnectionString("Default")));

// --- Kimlik doğrulama ---
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidIssuer = jwt.Issuer,
            ValidAudience = jwt.Audience,
            IssuerSigningKey = jwt.SigningKey(),
            NameClaimType = ClaimTypes.Name,
            RoleClaimType = ClaimTypes.Role,
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });
builder.Services.AddAuthorization();

// --- API altyapısı ---
builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
builder.Services.AddProblemDetails();
builder.Services.AddOpenApi(o => o.AddDocumentTransformer<BearerSecuritySchemeTransformer>());

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseAuthentication();
app.UseAuthorization();

// Demo projesi olduğu için API dokümanı her ortamda açık: /scalar
app.MapOpenApi();
app.MapScalarApiReference();

app.MapGet("/health", () => Results.Ok(new { status = "ok" })).WithTags("Health");
app.MapAuthEndpoints();
app.MapProductEndpoints();
app.MapMovementEndpoints();
app.MapReportEndpoints();
app.MapDashboardEndpoints();
app.MapCategoryEndpoints();
app.MapInsightEndpoints();
app.MapDemoEndpoints();
app.MapDemandEndpoints();

await DbInitializer.InitializeAsync(app.Services, app.Logger);

app.Run();

// Entegrasyon testlerinde WebApplicationFactory<Program> için.
public partial class Program;
