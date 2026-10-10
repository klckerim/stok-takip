using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using StokTakip.Api.Contracts;
using StokTakip.Api.Domain;
using Testcontainers.MsSql;

namespace StokTakip.Api.Tests;

/// <summary>
/// Gerçek SQL Server'a karşı uçtan uca testler. Docker çalışıyor olmalı.
/// </summary>
public class ApiFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _db = new MsSqlBuilder()
        .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
        .Build();

    public WebApplicationFactory<Program> Factory { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        await _db.StartAsync();
        Factory = new WebApplicationFactory<Program>().WithWebHostBuilder(b =>
        {
            b.UseEnvironment("Development");
            b.UseSetting("ConnectionStrings:Default", _db.GetConnectionString());
        });
        Factory.CreateClient(); // uygulamayı başlatır, veritabanı ve demo verisi oluşur
    }

    public async Task DisposeAsync()
    {
        await Factory.DisposeAsync();
        await _db.DisposeAsync();
    }
}

public class ApiTests(ApiFixture fixture) : IClassFixture<ApiFixture>
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() }
    };

    private const string PaletBarcode = "8690000000059"; // demo verisi: 60 adet
    private const string KoliBarcode = "8690000000028";  // demo verisi: 1200 adet

    private async Task<HttpClient> LoggedInClient(string user = "depo", string password = "Depo123!")
    {
        var client = fixture.Factory.CreateClient();
        var res = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest(user, password));
        res.EnsureSuccessStatusCode();
        var login = await res.Content.ReadFromJsonAsync<LoginResponse>(Json);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login!.Token);
        return client;
    }

    private static async Task<ProductDto> GetByBarcode(HttpClient client, string barcode) =>
        (await client.GetFromJsonAsync<ProductDto>($"/api/products/barcode/{barcode}", Json))!;

    [Fact]
    public async Task Login_with_wrong_password_returns_401()
    {
        var client = fixture.Factory.CreateClient();
        var res = await client.PostAsJsonAsync("/api/auth/login", new LoginRequest("depo", "yanlis"));
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
    }

    [Fact]
    public async Task Products_require_token()
    {
        var client = fixture.Factory.CreateClient();
        var res = await client.GetAsync($"/api/products/barcode/{PaletBarcode}");
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
    }

    [Fact]
    public async Task Unknown_barcode_returns_404()
    {
        var client = await LoggedInClient();
        var res = await client.GetAsync("/api/products/barcode/0000000000000");
        Assert.Equal(HttpStatusCode.NotFound, res.StatusCode);
    }

    [Fact]
    public async Task Out_more_than_stock_returns_409_and_stock_is_unchanged()
    {
        var client = await LoggedInClient();
        var before = await GetByBarcode(client, PaletBarcode);

        var res = await client.PostAsJsonAsync("/api/movements",
            new CreateMovementRequest(before.Id, MovementType.Out, before.Stock + 1, null, null), Json);

        Assert.Equal(HttpStatusCode.Conflict, res.StatusCode);
        Assert.Equal(before.Stock, (await GetByBarcode(client, PaletBarcode)).Stock);
    }

    [Fact]
    public async Task Same_client_request_id_is_applied_once()
    {
        var client = await LoggedInClient();
        var before = await GetByBarcode(client, KoliBarcode);
        var request = new CreateMovementRequest(before.Id, MovementType.In, 10, "test", Guid.NewGuid());

        var first = await client.PostAsJsonAsync("/api/movements", request, Json);
        var second = await client.PostAsJsonAsync("/api/movements", request, Json);

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal(before.Stock + 10, (await GetByBarcode(client, KoliBarcode)).Stock);
    }

    [Fact]
    public async Task Count_sets_stock_to_counted_quantity()
    {
        var client = await LoggedInClient();
        var product = await GetByBarcode(client, "8690000000035");

        var res = await client.PostAsJsonAsync("/api/movements",
            new CreateMovementRequest(product.Id, MovementType.Count, 77, "sayım", null), Json);
        var result = await res.Content.ReadFromJsonAsync<MovementResult>(Json);

        Assert.Equal(HttpStatusCode.Created, res.StatusCode);
        Assert.Equal(77, result!.NewStock);
        Assert.Equal(77, (await GetByBarcode(client, "8690000000035")).Stock);
    }

    [Fact]
    public async Task Only_admin_can_create_product()
    {
        var depo = await LoggedInClient();
        var res = await depo.PostAsJsonAsync("/api/products", new CreateProductRequest("123", "Test", "Adet"));
        Assert.Equal(HttpStatusCode.Forbidden, res.StatusCode);

        var admin = await LoggedInClient("admin", "Admin123!");
        res = await admin.PostAsJsonAsync("/api/products",
            new CreateProductRequest($"TEST-{Guid.NewGuid():N}", "Test Ürün", "Adet"));
        Assert.Equal(HttpStatusCode.Created, res.StatusCode);
    }
}
