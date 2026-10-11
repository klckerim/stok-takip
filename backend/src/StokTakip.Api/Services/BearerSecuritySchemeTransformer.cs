using Microsoft.AspNetCore.OpenApi;
using Microsoft.OpenApi;

namespace StokTakip.Api.Services;

/// <summary>
/// OpenAPI dokümanına JWT Bearer tanımını ekler; Scalar'da token bir kez girilir, tüm isteklerde kullanılır.
/// Kaynak: https://learn.microsoft.com/aspnet/core/fundamentals/openapi/customize-openapi?view=aspnetcore-10.0
/// </summary>
internal sealed class BearerSecuritySchemeTransformer : IOpenApiDocumentTransformer
{
    public Task TransformAsync(OpenApiDocument document, OpenApiDocumentTransformerContext context, CancellationToken cancellationToken)
    {
        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes = new Dictionary<string, IOpenApiSecurityScheme>
        {
            ["Bearer"] = new OpenApiSecurityScheme
            {
                Type = SecuritySchemeType.Http,
                Scheme = "bearer",
                In = ParameterLocation.Header,
                BearerFormat = "JWT",
                Description = "POST /api/auth/login ile alınan token."
            }
        };

        foreach (var operation in document.Paths.Values.Where(path => path.Operations is not null).SelectMany(path => path.Operations!))
        {
            operation.Value.Security ??= [];
            operation.Value.Security.Add(new OpenApiSecurityRequirement
            {
                [new OpenApiSecuritySchemeReference("Bearer", document)] = []
            });
        }

        return Task.CompletedTask;
    }
}
