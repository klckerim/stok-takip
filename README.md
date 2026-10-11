# Stok Takip — Barkodlu Depo ve Stok Uygulaması

[![CI](https://github.com/klckerim/stok-takip/actions/workflows/ci.yml/badge.svg)](https://github.com/klckerim/stok-takip/actions/workflows/ci.yml)

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
- **Tükenme tahmini:** özet ekranında "Yakında tükenecek" listesi (stok bu hızla kaç gün yeter, hangi gün biter); tedarik süresinden önce bitecekler kırmızı
- **Kritik seviye önerisi:** ürün ekranında günlük ortalama çıkış ve önerilen kritik seviye; yönetici tek dokunuşla uygular
- **Şüpheli hareket tespiti:** ürünün kendi geçmişine göre olağan dışı büyük çıkışlar ve büyük sayım farkları özet ekranında "İncelenmesi gereken hareketler" olarak listelenir
- **ML talep tahmini (ML.NET):** ürün ekranında önümüzdeki 14 günün günlük çıkış tahmini, %90 tahmin aralığı, grafik ve stoğun biteceği gün; modelin test dönemindeki hatası basit ortalamayla karşılaştırılarak gösterilir

- **Mobil:** Flutter (Android / iOS), kamerayla barkod okuma (`mobile_scanner`)
- **Backend:** ASP.NET Core 10 Minimal API, JWT ile giriş, rol bazlı yetki
- **Makine öğrenmesi:** ML.NET (Poisson regresyon), API içinde, dış servis yok
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

## Tahmin ve anomali tespiti nasıl çalışır

Makine öğrenmesi modeli değil; açıklanabilir istatistik. Küçük bir depoda birkaç aylık veriyle ML modeli eğitmek gürültüyü öğrenir; bu kurallar her sonucu "neden" sorusuna cevap verecek şekilde üretir. Hesaplar `Services/StockInsights.cs` içinde, veritabanından bağımsız saf fonksiyonlar olarak durur ve birim testleriyle doğrulanır.

| Ne | Nasıl |
| --- | --- |
| Günlük ortalama çıkış | Son 30 günün çıkış toplamı / 30. Ürün daha yeniyse pencere ilk hareketten bugüne kısaltılır (en az 7 gün), yoksa ortalama düşük çıkar. |
| Kaç gün yeter | Anlık stok / günlük ortalama çıkış |
| Önerilen kritik seviye | Günlük ortalama × (tedarik süresi 7 gün + emniyet payı 3 gün) |
| Olağan dışı çıkış | Son 60 günün çıkışlarına göre: ortalama + 3 standart sapmanın üstünde **ve** ortalamanın en az 2 katı. En az 5 geçmiş çıkış yoksa karar verilmez (az veriyle yanlış alarm olmasın). |
| Büyük sayım farkı | Fark, sistemdeki stoğun %10'unu aşıyorsa |

Eşikler `appsettings.json` → `Insights` bölümünden değiştirilir (ör. tedarikçiniz 3 günde getiriyorsa `LeadTimeDays: 3`).

**Demo geçmişi (sentetik):** Tahminlerin boş görünmemesi için geliştirme ortamında ilk açılışta her ürüne 120 günlük **üretilmiş** çıkış geçmişi yazılır: haftalık desen (pazartesi yoğun, cumartesi yarım gün, pazar kapalı), ürüne özgü artan/azalan eğilim ve gürültü. Anlık stok değişmez. Mevcut bir veritabanında yeniden üretmek için Scalar'da yönetici olarak `POST /api/demo/history` çağır; önceki demo hareketlerini silip baştan yazar ve ML modelini yeniden eğitir. Sadece `Development` ortamında açıktır; 10'dan fazla gerçek çıkışı olan ürünlere dokunmaz. Uygulama, modelin sentetik veriyle eğitildiğini ekranda belirtir.

## ML talep tahmini nasıl çalışır (ML.NET)

**Soru:** Bu ürün önümüzdeki 14 günde günde kaç adet çıkacak? Stok ne zaman biter?

**Yaklaşım:** Zaman serisini denetimli regresyona çevirmek (perakende talep tahmininde yaygın yöntem). Her örnek: "tahmin anında (origin) bilinenlerle, 1-14 gün sonraki bir günün çıkışı". Tüm ürünler **tek global modelle** eğitilir; ürün başına veri az olsa da toplamda binlerce örnek olur.

| Özellik | Neden |
| --- | --- |
| Hedef günün haftanın günü (one-hot) | Pazartesi yoğun, pazar kapalı gibi desenler |
| log(1 + son 7 gün ortalaması) | Yakın dönem seviyesi, eğilim |
| log(1 + son 28 gün ortalaması) | Genel seviye; ürünler arası ölçek farkını taşır |
| log(1 + son 4 haftada aynı günün ortalaması) | Ürüne özgü haftalık desen |
| Son 28 günde çıkışsız gün oranı | Seyrek satılan ürünler |

**Model:** `LbfgsPoissonRegression` (ML.NET). Günlük çıkış bir sayımdır: Poisson regresyonu negatif tahmin üretmez ve log bağlantısı sayesinde haftanın günü etkisini çarpan olarak öğrenir.

**Neden SSA (ML.NET zaman serisi) değil:** `ForecastBySsa` Intel MKL'e bağlıdır ve ARM64'te (Apple Silicon Mac, ARM sunucular) çalışmaz. Seçilen model tamamen yönetilen koddur; her mimaride çalışır.

**Doğrulama (zamana göre, veri sızıntısı yok):**
1. *Kalibrasyon:* Son 28 günden önceki veriyle eğit, sonraki 14 günü tahmin et. Ölçekli hataların (|gerçek − tahmin| / √(tahmin+1)) %90'lık dilimi tahmin aralığının genişliğini verir (split conformal). 14 günlük toplam ayrıca kalibre edilir; günlük hatalar birbirinden bağımsız değildir.
2. *Test:* Son 14 günden önceki veriyle eğit, son 14 günü tahmin et. Modelin hatası, "son 28 gün ortalaması" tahmininin hatası ve aralığın gerçek kapsama oranı ölçülür. **Bu sayılar uygulamada gösterilir**; model basit ortalamadan kötüyse bu da yazılır.
3. *Son model:* Tüm veriyle eğitilir, bugünden itibaren 14 gün tahmin edilir.

Sentetik demo verisinde (bilinen haftalık desen) model günlük hatayı basit ortalamaya göre yaklaşık %35 azaltır. Bu, yöntemin desen yakaladığını gösterir; **gerçek bir depoda başarıyı göstermez.** Gerçek veride ölçmek için en az 2-3 aylık kullanım gerekir.

**Çalışma şekli:** Model API açılışında ve 6 saatte bir (`Demand:RetrainHours`) arka planda eğitilir, bellekte tutulur. Tahmin isteği modeli eğitmez, sadece kullanır (birkaç ms). Yönetici `POST /api/ml/demand-model/train` ile hemen yeniden eğitebilir. Kod: `Services/Demand/` (özellikler ve eğitim akışı veritabanından bağımsız, birim testli).

**Bilinen sınırlar:** Kampanya, tatil, fiyat gibi dış etkenler modelde yok. Yeni ürün en az 28 günlük geçmiş ister. Çok büyük veride eğitim örnekleri seyreltilir (en fazla 300 bin satır).

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

Mobil:

```bash
cd mobile
flutter analyze
flutter test
```

**CI:** Her PR'da ve `main`'e her push'ta GitHub Actions (`.github/workflows/ci.yml`) ikisini de çalıştırır: Flutter `analyze` + `test` ve .NET `build` + `test` (gerçek SQL Server container'ıyla).

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
flutter run --dart-define=DEMO=true

# Gerçek telefon: bilgisayarın yerel IP'sini ver (telefon ve bilgisayar aynı Wi-Fi'de)
flutter run --dart-define=DEMO=true --dart-define=API_BASE_URL=http://192.168.1.20:8080
```

`DEMO=true` giriş ekranındaki demo hesap düğmelerini açar (şifreler uygulamaya gömülüdür). Gerçek kurulum derlemesinde bu bayrağı verme; varsayılan kapalıdır.

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
| GET | `/api/insights?days=30` | Giriş | `days` gün içinde tükenecek ürünler ve son 7 günün şüpheli hareketleri |
| GET | `/api/products/{id}/forecast` | Giriş | Günlük ortalama çıkış, kaç gün yeter, önerilen kritik seviye |
| GET | `/api/products/{id}/demand-forecast` | Giriş | ML.NET: 14 günlük günlük tahmin, %90 aralık, son 28 günün gerçek çıkışları, stok bitiş günü |
| GET | `/api/ml/demand-model` | Giriş | Modelin durumu: ne zaman, kaç örnekle eğitildi, test hatası ve kapsama |
| POST | `/api/ml/demand-model/train` | Admin | Modeli hemen yeniden eğit |
| POST | `/api/demo/history?days=120` | Admin (sadece Development) | Sentetik demo geçmişini sil ve yeniden üret, modeli yeniden eğit |

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
