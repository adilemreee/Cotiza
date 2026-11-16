# Cotiza

ABD'deki İspanyolca konuşan ustalar ve küçük müteahhitler için sesle teklif/fatura uygulaması (iOS 26+, SwiftUI).
Usta işi İspanyolca (ya da İngilizce) anlatır; uygulama kalemleri, miktarları ve fiyatları çıkarır, müşteriye
gönderilecek profesyonel bir PDF teklif üretir. Abonelik: haftalık, aylık ve yıllık (yıllıkta 3 gün deneme).

## Çalıştırma

```bash
open Cotiza.xcodeproj
```

Xcode'da `Cotiza` şemasını seçip Run. Şema `Cotiza/Resources/Products.storekit` dosyasını kullandığı için
satın alma akışı App Store Connect olmadan yerelde çalışır.

Proje dosyası `project.yml`'den üretilir. Dosya ekleyip çıkarınca:

```bash
xcodegen generate
```

Testler:

```bash
xcodebuild -project Cotiza.xcodeproj -scheme Cotiza -destination 'platform=iOS Simulator,name=iPhone Duo' test
```

## Ne var

| Alan | Dosya |
| --- | --- |
| Veri modeli (SwiftData) | `Cotiza/Models/Models.swift` |
| Teklif/fatura üretme kuralları, fiyat hafızası | `Cotiza/Models/DocumentFactory.swift` |
| Cihaz-içi AI (FoundationModels) + doğrulama | `Cotiza/Engine/EstimateEngine.swift` |
| AI yokken çalışan İspanyolca/İngilizce ayrıştırıcı | `Cotiza/Engine/RuleBasedParser.swift` |
| Ses tanıma | `Cotiza/Engine/SpeechRecorder.swift` |
| PDF | `Cotiza/Engine/PDFRenderer.swift` |
| Abonelik (StoreKit 2) | `Cotiza/Store/SubscriptionStore.swift`, `Cotiza/Views/PaywallView.swift` |
| Siri / Kestirmeler (yeni teklif, "ne kadar alacağım var", ödendi işaretle, belge aç) | `Cotiza/App/AppIntents.swift` |
| Spotlight indeksleme (açılışta ve arka plana geçerken) | `Cotiza/App/SpotlightIndexer.swift` |
| Paylaşılan veritabanı (uygulama + Siri aynı `ModelContainer`) | `Cotiza/App/AppDatabase.swift` |
| Ekranda müşteri imzası (Pro), PDF'e basılır, teklifi onaylar | `Cotiza/Views/SignatureView.swift` |
| SMS / WhatsApp ile gönderme, hazır müşteri mesajı (belge dilinde) | `Cotiza/Views/PDFPreviewView.swift`, `Cotiza/Engine/ClientMessage.swift` |
| Geçerlilik / vade tarihi, takip ve gecikme hatırlatmaları (yerel bildirim) | `Cotiza/App/ReminderScheduler.swift` |
| Kişiler'den müşteri seçme (izin istemeyen sistem seçicisi) | `Cotiza/Views/ContactPicker.swift` |
| Fiş tarama (Vision ile cihazda metin okuma + fiş ayrıştırıcı) | `Cotiza/Engine/ReceiptParser.swift`, `Cotiza/Views/ReceiptScanView.swift` |
| Ana ekran / kilit ekranı widget'ı (App Group üzerinden özet) | `CotizaWidget/`, `Cotiza/Shared/WidgetSnapshot.swift`, `Cotiza/App/WidgetData.swift` |
| Malzemeye kâr payı (fişten gelen maliyet saklanır, müşteriye kârlı fiyat gider) | `Money.withMarkup`, `LineItem.unitCost`, `Cotiza/Views/ReceiptScanView.swift` |
| Tekrarlayan faturalar (haftalık / 2 haftalık / aylık) + hatırlatma | `DocumentFactory.makeDueRepeats`, `RecurringInvoices`, `ReminderScheduler` |
| Kapora ve kısmi ödemeler (Pro): teklifte kapora yüzdesi, ödeme kaydı, PDF'te ödenenler + kalan bakiye, faturaya çevirince kapora faturaya taşınır, tamamı ödenince "ödendi" | `Payment` modeli, `DocumentFactory.record(payment:)`, `PaymentSheet` (`DocumentEditorView.swift`) |
| Kazanç / gider raporu, CSV + PDF dışa aktarma (Pro) | `Cotiza/Engine/ProfitReport.swift`, `Cotiza/Views/ReportView.swift` |
| iCloud senkronu (CloudKit özel veritabanı, olmazsa yerel) | `Cotiza/App/AppDatabase.swift` |
| İmza linki: müşteri teklifi tarayıcıda imzalar (Pro) | `Cotiza/Engine/SignLink.swift`, sunucu: `Server/sign` |
| Uygulama simgesi (Icon Composer belgesi: zemin + kâğıt, ses dalgası, satırlar katmanları; koyu modda dalga beyaz) | `Cotiza/Resources/AppIcon.icon`, 1024 px dışa aktarım: `AppStore/icon/AppIcon-1024.png` |
| Açılış ekranı + animasyonlu splash | `Cotiza/Views/SplashView.swift`, `LaunchBackground` / `LaunchMark` (görsel: `Tools/make_launch_mark.py`) |
| Çeviriler (EN kaynak; ES ve TR çeviri) | `Tools/make_strings.py` (TR: `Tools/strings_tr.py`) → `Cotiza/Resources/*.xcstrings`, `CotizaWidget/Localizable.xcstrings` |
| Türkçe: arayüz, belge dili (PDF, mesaj, rapor, imza), Türkçe iş tarifi ayrıştırma ("tanesi 120", "120'den", "toplam 600", "yirmi beş", "iki buçuk saat") | `DocumentLanguage.turkish`, `RuleBasedParser.turkishNumbers`, `CotizaTests/TurkishTests.swift` |
| App Store Connect metinleri (EN + ES) | `AppStore/AppStoreConnect.md` (`python3 AppStore/check_lengths.py` sınırları kontrol eder) |
| Web sitesi (https://cotiza.adilemree.xyz, EN + ES + TR: `/`, `/es/`, `/tr/`) | `Tools/build_site.py` → `AppStore/site`, yayınlama: `Tools/deploy_site.sh` |
| UI testleri (tüm ekranları gezer) | `CotizaUITests/CotizaUITests.swift` |

Ücretsiz plan: 3 teklif, PDF altında "Made with Cotiza". Pro: sınırsız teklif, faturaya çevirme, ödeme kaydı, logo, markasız PDF.

Gelir nakit esasına göre sayılır: her ödeme kendi tarihinde, "ödendi" diye işaretlenen belgede kalan kısım o gün.
Kısmi ödenen bir işin gelir, vergi ve malzeme payı raporda ödeme oranına göre bölünür.

Yeni bir arayüz metni eklediğinde önce betiğin okuduğu klasöre derle, sonra betiği çalıştır. İspanyolcası ya da Türkçesi eksik
anahtar varsa betik hata verir.

```bash
xcodebuild -project Cotiza.xcodeproj -scheme Cotiza -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build/DerivedData build
```

```bash
python3 Tools/make_strings.py
```

### Yalnızca DEBUG derlemesinde çalışan başlatma argümanları

- `-CotizaDemoData YES` — örnek işletme profiliyle, onboarding'i atlayarak açar
- `-CotizaDemoTranscript "…"` — sesli kayıt ekranını hazır metinle açar
- `-CotizaMockPlans YES` — StoreKit ürünleri yüklenemezse paywall'da örnek planlar gösterir
- `-CotizaForcePro YES` — Pro'yu açık sayar
- `-CotizaResetState YES` — temiz kurulum gibi başlatır (UI testleri kullanır)
- `-CotizaScreen <capture|editor|pdf|signature|home|report|paywall>` — App Store ekran görüntüleri için o ekranı
  örnek veriyle doğrudan açar (`Tools/screenshots.sh` kullanır)
- `-CotizaInitCloudKitSchema YES` — tüm iCloud şemasını Development'a yazar ve uygulamayı kapatır (bkz. "App Store'a
  göndermeden önce" 3. madde)
- Ortam değişkeni `CotizaCloudKitReport=1` — iCloud'da bu kullanıcı için ne kayıtlı olduğunu türlere göre sayar,
  `Documents/cloudkit-report.txt`'e ve konsola yazar; `CotizaCloudKitLookup=<kayıt adı>,…` ile tek tek kayıt sorar.
  `CotizaCloudKitDebug=1` her senkron adımını hatasıyla birlikte konsola yazar. Telefonda:
  `xcrun devicectl device process launch --device <UDID> --console --environment-variables '{"CotizaCloudKitReport":"1"}' com.cotiza.app`
- `-CotizaDemoPaid YES` — (`-CotizaDemoData` ile) bu ay ödenmiş 3 iş, fiş maliyetleri ve aylık tekrar; rapor ve
  tekrarlayan faturaları denemek için

## Doğrulanan ve doğrulanmayan

Doğrulandı (iPhone Duo simülatörü, iOS 27.2):

- 77 birim testi: ayrıştırıcı, AI çıktısı doğrulaması, vergi/toplam, PDF (tek ve çok sayfa, İspanyolca etiketler),
  ücretsiz limit, `Products.storekit` üzerinden gerçek satın alma akışı, Siri özet hesabı, belge kimliği onarımı, fiş ayrıştırma (Vision ile gerçek görüntü dahil), müşteri mesajı,
  hatırlatma planı, imza, tarihler, widget özeti, Kişiler alanları, imzalı PDF, kapora ve kısmi ödemeler (bakiye, faturaya taşınma, rapor bölüşümü, PDF, müşteri mesajı)
- Uçtan uca akış elle: profil → iş tarifi → kalemler → müşteri → PDF önizleme; İngilizce ve İspanyolca arayüz

Doğrulanmadı — gerçek cihazda denenmeli:

- **Cihaz-içi AI yolu.** Simülatör model çıkarımını desteklemiyor, geliştirme Mac'inde de model hazır değildi.
  Kod derleniyor ve hata durumunda ayrıştırıcıya düştüğü görüldü, ama modelin ürettiği İngilizce metnin kalitesi
  hiç görülmedi. Apple Intelligence açık bir iPhone'da (15 Pro ve sonrası) denenmeli.
- **Mikrofon ve ses tanıma.** Simülatörde denenmedi.
- **Çeviri yedeği** (AI olmayan cihazlarda Translation çerçevesi). Simülatörde desteklenmiyor.
- **Siri ve Spotlight.** Niyetler, belge varlığı ve 9 Siri cümlesi derlenen metadata'da görünüyor, indeksleme
  hata vermiyor. Ama Siri'ye sesle sorma, Spotlight'ta arayıp sonuca dokunma ve Kestirmeler uygulaması
  simülatörde denenemedi.
- **SMS ve WhatsApp gönderimi, kamerayla fiş tarama, bildirimlerin gerçekten gelmesi.** Simülatörde mesaj
  uygulaması ve WhatsApp yok, kamera yok. Fotoğraftan fiş okuma, imza, Kişiler seçici ve widget simülatörde
  elle denendi.
- **iCloud senkronu.** Simülatörde iCloud hesabı yok. Modellerin CloudKit'e uygun olduğu (açılışta şema
  doğrulama hatası yok) ve hesap yokken uygulamanın yerelde çalıştığı görüldü. İki cihaz arası gerçek senkron
  denenmedi.
- **Standart iPhone genişliği.** Makinede yalnızca katlanabilir "iPhone Duo" simülatörü kurulu.

## İmza linki servisi (`Server/sign`)

Bağımlılığı olmayan küçük bir Node servisi (Node'un kendi `http` ve `sqlite` modülleri). Sunucuda
`/opt/cotiza-sign` altında Docker ile çalışır (`127.0.0.1:4130`); Cotiza sitesinin nginx ayarı `/s/` ve
`/api/v1/` yollarını ona yönlendirir, dışarıya mevcut Cloudflare tüneli açar.

- Uygulama teklifi (PDF + sayfada görünecek metin) her link için rastgele bir gizli anahtarla yükler. Anahtar
  belgede saklanır ve iCloud ile senkronlanır; imzayı yalnızca o anahtarı bilen cihazlar okuyabilir.
- Müşteri `cotiza.adilemree.xyz/s/<id>` sayfasında adını yazıp imzalar. Uygulama öne geldiğinde ve arka planda
  (`BGAppRefreshTask`, iOS ne zaman isterse) kontrol eder, imzayı belgeye işler, bildirim gösterir ve
  kaydı sunucudan siler. Toplanmayan kayıtlar 30 günde kendiliğinden silinir; veri yedeklenmez.

```bash
cd Server/sign && node --test
```

İmza sayfası İngilizce, İspanyolca ve Türkçe (`page.js`, bağlantı önizleme kartları `Tools/make_link_card.py`).
Belgenin dili hangisiyse müşteri sayfayı o dilde görür. Sunucuya yükleme (testler geçmezse durur, nginx ayarını
yedekleyip yalnızca geçerliyse yeniler):

```bash
Tools/deploy_sign.sh
```

## App Store'a göndermeden önce

1. `project.yml` içinde `DEVELOPMENT_TEAM` ve `PRODUCT_BUNDLE_IDENTIFIER` (şu an `com.cotiza.app`).
2. Apple Developer hesabında `group.com.cotiza.app` App Group'unu oluştur ve hem `com.cotiza.app` hem
   `com.cotiza.app.widget` kimliklerine ekle (widget özeti için). Veritabanı App Group'ta değil, uygulamanın kendi
   klasöründe kalır.
3. iCloud: Apple Developer hesabında `iCloud.com.cotiza.app` CloudKit container'ını oluştur ve uygulama
   kimliğine iCloud (CloudKit) + Push Notifications yetkilerini ekle. Şemayı oluşturmak için Xcode'da
   Product → Scheme → Edit Scheme → Run → Arguments'ta `-CotizaInitCloudKitSchema YES` kutusunu işaretle,
   iCloud'a girişli bir iPhone'da bir kez çalıştır (konsolda "✅ CloudKit schema created" yazar, uygulama
   kendini kapatır), kutuyu kaldır. Bu, tüm kayıt türlerini ve alanları Development ortamına yazar; uygulamayı kullanarak oluşan şemada
   hiç doldurulmamış alanlar eksik kalır. **Yayından önce CloudKit Console'da şemayı Production'a "Deploy"
   et**, yoksa App Store ve TestFlight sürümlerinde senkron çalışmaz. Modele alan eklerken yalnızca yeni alan ekle
   (silme / yeniden adlandırma CloudKit'te yapılamaz).
4. App Store Connect'te bir abonelik grubu ve iki ürün; kimlikleri koddakiyle aynı olmalı:
   `com.cotiza.app.pro.yearly` (3 gün ücretsiz deneme), `com.cotiza.app.pro.monthly` ve `com.cotiza.app.pro.weekly`.
   Paket kimliğini değiştirirsen `SubscriptionStore.swift` ve `Products.storekit` içindekileri de değiştir.
5. Gizlilik, destek ve koşullar sayfaları https://cotiza.adilemree.xyz adresinde yayında (sunucuda nginx
   `127.0.0.1:8133` + Cloudflare tüneli; ayar `AppStore/server/nginx-cotiza.conf`). Uygulamadaki bağlantılar
   `AppLinks` içinde.
6. "Cotiza" adının App Store'da ve marka olarak uygunluğu kontrol edilmedi.
7. Fiyatlar ($14.99/ay, $99.99/yıl) `Products.storekit` içinde yalnızca yerel test içindir; gerçek fiyat
   App Store Connect'te belirlenir.
8. Ekran görüntüleri, açıklama, gizlilik beyanı (uygulama veri toplamıyor; her şey cihazda).
