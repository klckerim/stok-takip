# Stok Takip — Barkodlu Depo ve Stok Uygulaması

Depo personeli telefonla ürün barkodunu okutur; giriş, çıkış veya sayım kaydeder. Stok anında güncellenir.

**Özellikler**

- Giriş ekranı: demo hesaplarla tek dokunuşla giriş, sunucu bağlantı durumu, uygulama içinden sunucu adresi ayarı

- Özet ekranı: toplam ürün, kritik stok, bugünkü giriş/çıkış/sayım, kritik ürünler, son hareketler
- Hareketler ekranı: tüm depo hareketleri, tipe (giriş/çıkış/sayım) ve döneme (bugün/7/30 gün) göre filtre
- Hızlı miktar düğmeleri (+1, +5, +10, +50)
- Seri sayım / toplu giriş / toplu çıkış: barkodlar art arda okutulur, her okutma +1, sonunda tek seferde kaydedilir (çevrimdışıysa kuyruğa alınır)
- Kategoriler: ürün listesinde kategori filtresi, yönetici ürün eklerken/düzenlerken yeni kategori açabilir
- Ürün düzenleme (yönetici): ad, birim, kategori, kritik seviye

- Kamerayla barkod okuma (okununca titreşim), elle barkod girişi
- Giriş / çıkış / sayım; eksi stoğa düşmeyi engeller
- Ürün ekranında son hareketler: kim, ne zaman, ne yaptı
- Kritik stok seviyesi: altına düşen ürün listede kırmızı görünür, "Sadece kritik stok" filtresi
- Bilinmeyen barkod okutulursa yönetici ürünü telefondan ekler (açılış stoğu ve kritik seviyeyle)
- Rol bazlı yetki: depo personeli hareket girer, yönetici ürün ekler ve kritik seviyeyi değiştirir
- Çevrimdışı çalışma: depoda bağlantı yokken giriş/çıkış/sayım telefonda kuyruğa alınır, bağlantı gelince kendiliğinden gönderilir
- Excel raporları (stok ve son 30 gün hareketleri): telefondan indirip WhatsApp, e-posta veya Dosyalar ile paylaşma

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
- **Idempotency.** Mobil her kayıt için bir `clientRequestId` (GUID) üretir. Zayıf Wi-Fi'de istek tekrar gönderilirse hareket iki kez yazılmaz.
- **Çevrimdışı kuyruk.** Sunucuya ulaşılamazsa hareket cihazda (SharedPreferences) saklanır; uygulama açılınca, ön plana gelince ve 30 sn'de bir gönderilmeye çalışılır. Aynı `clientRequestId` kullanıldığı için istek aslında sunucuya ulaşmış olsa bile çift kayıt oluşmaz. Hareket, gönderildiği an değil gerçekten yapıldığı an (`occurredAtUtc`) ile kaydedilir. Ürün listesi önbelleğe alındığı için barkod okutma da çevrimdışı çalışır.
- **Bilinen sınır.** Çevrimdışı sayım, gönderildiği andaki stoğa göre fark yazar; arada başka cihazdan hareket girildiyse sayım onu da düzeltmiş sayılır. Sunucu, stoktan fazla çıkışı gönderim anında reddeder; reddedilen kayıt "Gönderilmeyi bekleyenler" ekranında sebebiyle görünür, tekrar denenebilir ya da silinebilir.

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

**Sunucu adresi uygulama içinden de değiştirilebilir:** giriş ekranında sağ üstteki ayar ikonu → adresi yaz → "Bağlantıyı test et" → Kaydet. Adres cihazda saklanır; Mac'in IP'si değişince yeniden derlemek gerekmez.

**Uygulama ikonu:** `flutter pub get && dart run flutter_launcher_icons` (kaynak: `mobile/assets/icon/app_icon.png`).

## API

| Metot | Yol | Yetki | Açıklama |
| --- | --- | --- | --- |
| POST | `/api/auth/login` | Herkes | Token al |
| GET | `/api/products?search=&criticalOnly=&categoryId=` | Giriş | Ürünler, anlık stok, kritik durumu |
| GET | `/api/products/barcode/{barcode}` | Giriş | Barkodla ürün + stok |
| GET | `/api/products/{id}/movements` | Giriş | Son hareketler |
| POST | `/api/products` | Admin | Ürün ekle (açılış stoğu ve kritik seviye isteğe bağlı) |
| PUT | `/api/products/{id}` | Admin | Ad, birim, kategori, kritik seviye güncelle |
| GET | `/api/categories` | Giriş | Kategoriler ve ürün sayıları |
| POST | `/api/categories` | Admin | Kategori ekle |
| DELETE | `/api/categories/{id}` | Admin | Kategori sil (ürünler kategorisiz kalır) |
| POST | `/api/movements` | Giriş | Giriş / çıkış / sayım (`In`, `Out`, `Count`) |
| GET | `/api/dashboard` | Giriş | Özet ekranı verisi |
| GET | `/api/movements?type=&days=7&productId=` | Giriş | Tüm hareketler, filtreli |
| GET | `/api/reports/stock.xlsx` | Giriş | Stok raporu (Excel) |
| GET | `/api/reports/movements.xlsx?days=30` | Giriş | Hareket raporu (Excel) |

Scalar'da (`/scalar`) önce login ol, dönen token'ı **Authentication → Bearer** alanına bir kez yapıştır; tüm isteklerde kullanılır.

## Veritabanı şeması değişince (EF Core migrations)

Uygulama açılışta bekleyen migration'ları kendisi uygular; veri silinmez.

```bash
dotnet tool install --global dotnet-ef        # bir kez
cd backend/src/StokTakip.Api
dotnet ef migrations add AlanAdi --output-dir Data/Migrations
cd ../.. && docker compose up -d --build
```

## Sonraki adımlar

- [ ] Yönetim paneli (Razor Pages): ürün ve kullanıcı yönetimi
- [ ] Canlıya alma: VPS + Docker Compose + domain + HTTPS (Caddy veya Nginx), APK indirme linki
- [ ] README'ye ekran görüntüleri ve 2 dakikalık demo videosu
