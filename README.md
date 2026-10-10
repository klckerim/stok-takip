# Stok Takip — Barkodlu Depo ve Stok Uygulaması

Depo personeli telefonla ürün barkodunu okutur; giriş, çıkış veya sayım kaydeder. Stok anında güncellenir.

**Özellikler**

- Kamerayla barkod okuma (okununca titreşim), elle barkod girişi
- Giriş / çıkış / sayım; eksi stoğa düşmeyi engeller
- Ürün ekranında son hareketler: kim, ne zaman, ne yaptı
- Kritik stok seviyesi: altına düşen ürün listede kırmızı görünür, "Sadece kritik stok" filtresi
- Bilinmeyen barkod okutulursa yönetici ürünü telefondan ekler (açılış stoğu ve kritik seviyeyle)
- Rol bazlı yetki: depo personeli hareket girer, yönetici ürün ekler ve kritik seviyeyi değiştirir

- **Mobil:** Flutter (Android / iOS), kamerayla barkod okuma (`mobile_scanner`)
- **Backend:** ASP.NET Core 10 Minimal API, JWT ile giriş, rol bazlı yetki
- **Veritabanı:** SQL Server, EF Core
- **Test:** xUnit + Testcontainers (gerçek SQL Server'a karşı entegrasyon testleri)
- **Çalıştırma:** Docker Compose

```
mobile/   Flutter uygulaması
backend/  .NET API + testler + docker-compose
```

## Tasarım kararları

- **Stok tablosu yok, hareket tablosu var.** Anlık stok = hareketlerin toplamı. Her değişikliğin kim tarafından, ne zaman yapıldığı kayıtlı kalır.
- **Sayım = düzeltme hareketi.** Sayılan miktar girilir; sistem farkı (sayılan − mevcut) hareket olarak yazar.
- **Eksi stok yok.** Çıkışlar `Serializable` transaction içinde kontrol edilir; aynı anda iki çıkış stoğu eksiye düşüremez.
- **Idempotency.** Mobil her kayıt için bir `clientRequestId` (GUID) üretir. Zayıf Wi-Fi'de istek tekrar gönderilirse hareket iki kez yazılmaz. İleride offline senkronun da temeli bu.

## 1. Backend'i çalıştır

Gereken: Docker Desktop.

```bash
cd backend
docker compose up -d --build
```

- API: http://localhost:8080
- API dokümanı ve deneme ekranı: http://localhost:8080/scalar
- Sağlık kontrolü: http://localhost:8080/health

İlk açılışta veritabanı ve demo verisi otomatik oluşur.

| Kullanıcı | Şifre | Rol |
| --- | --- | --- |
| `admin` | `Admin123!` | Admin (ürün ekleyebilir) |
| `depo` | `Depo123!` | Depo personeli |

Demo barkodlar: `8690000000011`, `8690000000028`, `8690000000035`, `8690000000042`, `8690000000059`

**Docker olmadan:** SQL Server Express kur, `backend/src/StokTakip.Api/appsettings.json` içindeki bağlantı cümlesini düzenle, sonra:

```bash
cd backend/src/StokTakip.Api
dotnet run
```

## 2. Testleri çalıştır

Docker açık olmalı (testler geçici bir SQL Server container'ı başlatır).

```bash
cd backend
dotnet test
```

## 3. Mobil uygulamayı çalıştır

Gereken: Flutter SDK, Android Studio (emülatör) veya USB hata ayıklaması açık bir Android telefon.

```bash
cd mobile
flutter create --platforms=android,ios --org com.stoktakip .   # android/ ve ios/ klasörlerini üretir (lib/'e dokunmaz)
flutter pub get
```

**Bir kez yapılacak ayarlar:**

- `android/app/src/main/AndroidManifest.xml` içinde `<application` etiketine şunu ekle (geliştirmede HTTP için; canlıda HTTPS kullanılacak):
  ```xml
  android:usesCleartextTraffic="true"
  ```
- `ios/Runner/Info.plist` içine kamera izni açıklaması ekle:
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>Barkod okumak için kamera gerekiyor.</string>
  ```

**Çalıştır:**

```bash
# Android emülatörü (bilgisayardaki API'ye 10.0.2.2 ile gider)
flutter run

# Gerçek telefon: bilgisayarın yerel IP'sini ver (telefon ve bilgisayar aynı Wi-Fi'de)
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080
```

Emülatörde kamera yoksa barkod ekranındaki **Elle gir** ile demo barkodlardan birini yaz.

## API

| Metot | Yol | Yetki | Açıklama |
| --- | --- | --- | --- |
| POST | `/api/auth/login` | Herkes | Token al |
| GET | `/api/products?search=&criticalOnly=` | Giriş | Ürünler, anlık stok, kritik durumu |
| GET | `/api/products/barcode/{barcode}` | Giriş | Barkodla ürün + stok |
| GET | `/api/products/{id}/movements` | Giriş | Son hareketler |
| POST | `/api/products` | Admin | Ürün ekle (açılış stoğu ve kritik seviye isteğe bağlı) |
| PUT | `/api/products/{id}` | Admin | Ad, birim, kritik seviye güncelle |
| POST | `/api/movements` | Giriş | Giriş / çıkış / sayım (`In`, `Out`, `Count`) |

## Sonraki adımlar

- [ ] `EnsureCreated` yerine EF Core migrations (`dotnet ef migrations add Initial`, açılışta `Migrate()`)
- [ ] Yönetim paneli (Razor Pages): ürün ekleme, stok raporu, Excel'e aktarma
- [ ] Offline sayım: internet yokken cihazda kuyruğa al, bağlantı gelince gönder
- [ ] Canlıya alma: VPS + Docker Compose + domain + HTTPS (Caddy veya Nginx), APK indirme linki
- [ ] README'ye ekran görüntüleri ve 2 dakikalık demo videosu
