using Microsoft.ML;
using Microsoft.ML.Data;

namespace StokTakip.Api.Services.Demand;

/// <summary>
/// ML.NET modeli: özellik normalizasyonu + Poisson regresyon (L-BFGS).
/// Poisson: hedef bir sayım (günlük çıkış adedi), tahmin hiçbir zaman negatif olmaz ve
/// log bağlantısı sayesinde haftanın günü etkisi çarpan olarak öğrenilir ("pazar ≈ 0, pazartesi ×1,25").
/// Tamamen yönetilen (.NET) kod: Intel MKL gerektirmez, Apple Silicon / ARM64 dahil her yerde çalışır.
/// (ML.NET'in SSA zaman serisi modeli MKL'e bağlı olduğu için ARM64'te çalışmaz; bilinçli olarak seçilmedi.)
/// </summary>
public sealed class DemandModel
{
    public const string Algorithm = "ML.NET LbfgsPoissonRegression";

    private readonly MLContext _ml;
    private readonly ITransformer _model;

    private DemandModel(MLContext ml, ITransformer model)
    {
        _ml = ml;
        _model = model;
    }

    public static DemandModel Train(MLContext ml, IReadOnlyList<DemandExample> examples)
    {
        var data = ml.Data.LoadFromEnumerable(examples.Select(e => new Row { Label = e.Label, Features = e.Features }));

        var pipeline = ml.Transforms.NormalizeMeanVariance(nameof(Row.Features))
            .Append(ml.Regression.Trainers.LbfgsPoissonRegression(
                labelColumnName: nameof(Row.Label),
                featureColumnName: nameof(Row.Features),
                l1Regularization: 0f,
                l2Regularization: 0.01f));

        return new DemandModel(ml, pipeline.Fit(data));
    }

    /// <summary>Günlük beklenen çıkış (≥ 0). Thread-safe: her çağrı kendi veri görünümünü kullanır.</summary>
    public float[] Predict(IReadOnlyList<float[]> features)
    {
        if (features.Count == 0) return [];
        var data = _ml.Data.LoadFromEnumerable(features.Select(f => new Row { Features = f }));
        return _ml.Data.CreateEnumerable<Prediction>(_model.Transform(data), reuseRowObject: false)
            .Select(p => float.IsFinite(p.Score) ? Math.Max(0f, p.Score) : 0f)
            .ToArray();
    }

    private sealed class Row
    {
        public float Label { get; set; }

        [VectorType(DemandFeatures.Count)]
        public float[] Features { get; set; } = [];
    }

    private sealed class Prediction
    {
        public float Score { get; set; }
    }
}
