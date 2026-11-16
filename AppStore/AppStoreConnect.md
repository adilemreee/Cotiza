# Cotiza — App Store Connect metinleri

Kopyala-yapıştır için hazır. Karakter sınırları `python3 AppStore/check_lengths.py` ile kontrol edildi.

Dil sırası: **English (U.S.)** ana dil, **Spanish (Mexico)** ek dil. ABD App Store'u İspanyolca cihaz
kullanan kişilere Spanish (Mexico) metinlerini gösterir; hedef kitle bu. **Turkish** isteğe bağlı üçüncü dil: Türkiye
mağazası ve Türkçe cihazlar için (4. bölüm).

### Ad ve anahtar kelime stratejisi

- **Ad, en çok aranan iki kelimeyi taşır.** Ustalar uygulamayı ne yaptığıyla arar: "estimate", "invoice",
  "factura", "presupuesto". Apple'ın aramasında en ağır basan alan addır; "by voice" gibi bir özelliği değil,
  aranan kelimeyi buraya koyuyoruz. Ana ekranda görünen ad yine kısaca "Cotiza".
- **Alt başlık, farkı söyler.** Sesle teklif ("voice quotes / cotizaciones por voz") ve kitle ("contractors") ya da
  Pro'nun en güçlü özelliği ("firma"). Bunlar da aramada sayılır.
- **ABD mağazası iki dili birlikte okur.** English (U.S.) ve Spanish (Mexico) adı, alt başlığı ve anahtar
  kelimeleri ABD'deki aramada birlikte sayılır. Bu yüzden iki dil arasında hiçbir kelime tekrar edilmez:
  toplam ~200 bayt anahtar kelime alanı boşa gitmez.
- **Anahtar kelimelerde addaki ve alt başlıktaki kelimeler yok.** Apple onları zaten sayıyor. "maker" tek başına
  yazılır; Apple onu addaki "invoice" ve "estimate" ile birleştirip "invoice maker" / "estimate maker"
  aramalarında gösterir.
- **Rakip adı yok.** Başka uygulamaların adını anahtar kelimeye koymak reddedilme sebebidir.

---

## 1. App Information

| Alan | Değer |
| --- | --- |
| Bundle ID | `com.cotiza.app` |
| SKU | `cotiza-ios-001` |
| Primary category | Business |
| Secondary category | Productivity |
| Content rights | Does not contain third-party content |
| Age rating | Tüm sorulara **None / No** → 4+ |
| Price | Free (abonelik uygulama içinden) |
| Privacy Policy URL (English) | `https://cotiza.adilemree.xyz/privacy` |
| Privacy Policy URL (Spanish) | `https://cotiza.adilemree.xyz/es/privacy` |
| Support URL (English) | `https://cotiza.adilemree.xyz/support` |
| Support URL (Spanish) | `https://cotiza.adilemree.xyz/es/support` |
| Privacy Policy URL (Turkish) | `https://cotiza.adilemree.xyz/tr/privacy` |
| Support URL (Turkish) | `https://cotiza.adilemree.xyz/tr/support` |
| Marketing URL (English / Spanish / Turkish) | `https://cotiza.adilemree.xyz/` / `https://cotiza.adilemree.xyz/es/` / `https://cotiza.adilemree.xyz/tr/` |
| Copyright | `2026 Adil Emre Karayürek` |

Gizlilik ve destek adresleri her dil için ayrı girilir; İspanyolca (Mexico) sayfasında `/es/`, Türkçede `/tr/` adreslerini kullan.
Site kaynağı `AppStore/site`, yayınlamak için `Tools/deploy_site.sh`.

---

## 2. English (U.S.)

**Name** (30)
```
Cotiza: Estimates & Invoices
```

**Subtitle** (30)
```
Voice quotes for contractors
```

**Promotional text** (170)
```
Describe the job out loud in Spanish or English. Cotiza turns it into a clean, professional estimate your client can approve on the spot.
```

**Keywords** (100 byte, virgülden sonra boşluk yok)
```
maker,bid,proposal,handyman,painter,landscaping,cleaning,roofing,plumber,receipt,signature,billing
```

**Description** (4000)
```
Win more jobs by sending a professional estimate before you leave the driveway.

Cotiza is built for contractors and small crews who'd rather talk than type. Describe the job out loud — in Spanish, English, or a mix of both — with your quantities and prices. Cotiza turns it into line items, adds them up and creates a clean PDF estimate with your business name, ready to text or email to your client.

SAY IT, DON'T TYPE IT
"Paint two bedrooms at 350 each, install 3 doors at 120 each and 8 hours of labor at 45 an hour. Client Maria Lopez."
Cotiza picks out each task, the quantity, the unit and the price. You review it, fix anything with a tap, and send.

SPEAK SPANISH, SEND ENGLISH
Talk in the language you think in. Your client receives a clear estimate in the language they read. Every document can be set to English or Spanish.

CLOSE THE JOB, EVEN FROM AFAR
Your client signs with a finger on your phone, or from a link you send by text or WhatsApp. The estimate is approved, you get a notification, and the signature is printed on the PDF with the date. No printer, no paper.

LOOK PROFESSIONAL
• Clean PDF estimates and invoices with your business details, license number, terms and valid-until or due dates
• Sales tax that applies only to the items you mark taxable
• Notes for the client: timeline, deposit, what's included

GET PAID FASTER
• Send by text message or WhatsApp, with a ready-made note in your client's language
• Ask for a deposit, record each payment and see the balance due
• Turn an approved estimate into an invoice in one tap; the deposit carries over
• Reminders when an estimate has no answer after 3 days or an invoice is past due
• Recurring invoices for weekly or monthly clients, ready on the day with a reminder
• See what's waiting for an answer and what you've been paid this month

KNOW WHAT YOU MADE
• Scanned receipts keep your cost; Cotiza adds your markup (15% by default) to what the client pays
• Monthly and yearly reports: revenue, sales tax collected, materials cost and profit per job
• Export a spreadsheet (CSV) or PDF for your accountant at tax time

LESS TYPING
• Scan a store receipt and add the materials to the invoice
• Pick a client from your Contacts
• Home Screen and Lock Screen widgets, and Siri: "How much am I owed in Cotiza?"

ON ALL YOUR DEVICES
Your jobs sync through your private iCloud, so they're on your new iPhone and your iPad. We never see them.

GETS FASTER EVERY TIME
Cotiza remembers the prices you use, so your usual work fills in by itself.

PRIVATE BY DESIGN
No account, no sign-up. Your jobs, clients and prices are stored on your phone and in your private iCloud. On iPhones with Apple Intelligence, the estimate is written by Apple's on-device model; your job description is not sent to us. A signing link you send is deleted from our server once it's signed.

Made for painters, landscapers, cleaners, handymen, roofers, flooring, drywall, concrete, plumbing, electrical and HVAC pros, and general contractors.

COTIZA PRO
Try Cotiza free with 3 estimates. Cotiza Pro gives you unlimited estimates, invoices, recurring invoices, deposits and partial payments, client signatures, profit reports, your logo on every document and no Cotiza branding. Choose weekly, monthly or yearly; the yearly plan starts with a 3-day free trial for new subscribers.

Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically unless it is canceled at least 24 hours before the end of the current period. Your account is charged for renewal within 24 hours before the end of the current period. Manage or cancel anytime in your App Store account settings. Any unused portion of a free trial is forfeited when you purchase a subscription.

Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Subscription terms: https://cotiza.adilemree.xyz/terms
Privacy Policy: https://cotiza.adilemree.xyz/privacy
```

**What's New** (4000) — 1.1.1 (1.1.0 ayrıca yayınlanmadığı için onun notlarını da içerir)
```
Deposits and partial payments

• Ask for a deposit on your estimates. Set your usual percentage once in Settings. The deposit is printed on the PDF, on the signing page and in the message to your client.
• Record each payment: the amount, the date and how your client paid (cash, check, Zelle, Cash App, Venmo or card).
• Invoices list what was paid and show the balance due. A deposit paid on the estimate carries over to the invoice.
• When everything is paid, the job is marked paid by itself.
• The home screen shows what each client still owes, and overdue reminders mention the balance, not the full total.
• Reports count every payment on the day you got it, deposits included.
• A cleaner estimate and invoice screen: dates, repeat, deposit percentage, language and status are now tucked under More options.
• Cotiza now speaks Turkish: the app, voice input and documents.

Recording payments is part of Cotiza Pro.
```

---

## 3. Spanish (Mexico)

**Name** (30)
```
Cotiza: Factura y Presupuesto
```

**Subtitle** (30)
```
Cotizaciones por voz y firma
```

**Promotional text** (170)
```
Describe el trabajo en voz alta, en español o en inglés. Cotiza lo convierte en una cotización profesional que tu cliente puede aprobar ahí mismo.
```

**Keywords** (100 byte)
```
contratista,pintor,jardineria,limpieza,techos,plomero,remodelacion,recibo,cobrar,ganancias,estimado
```

**Description** (4000)
```
Gana más trabajos enviando una cotización profesional antes de irte de la casa del cliente.

Cotiza está hecho para contratistas y cuadrillas que prefieren hablar en vez de escribir. Describe el trabajo en voz alta —en español, en inglés o mezclando los dos— con tus cantidades y precios. Cotiza lo convierte en conceptos, suma todo y crea una cotización en PDF con el nombre de tu negocio, lista para mandar por mensaje o correo.

DILO, NO LO ESCRIBAS
"Pintar dos recámaras a 350 cada una, instalar 3 puertas a 120 cada una y 8 horas de mano de obra a 45 la hora. Cliente María López."
Cotiza saca cada trabajo, la cantidad, la unidad y el precio. Lo revisas, corriges lo que quieras con un toque y lo envías.

HABLA ESPAÑOL, ENVÍA EN INGLÉS
Habla en el idioma en que piensas. Tu cliente recibe una cotización clara en el idioma que lee. Cada documento puede ir en inglés o en español.

CIERRA EL TRATO, AUNQUE NO ESTÉS
Tu cliente firma con el dedo en tu teléfono o desde un enlace que le mandas por mensaje o WhatsApp. La cotización queda aprobada, te avisa Cotiza y la firma sale en el PDF con la fecha. Sin papel.

LUCE PROFESIONAL
• Cotizaciones y facturas en PDF con los datos de tu negocio, número de licencia, términos y fecha de vigencia o de pago
• Impuesto de venta que solo se aplica a los conceptos que marques

COBRA MÁS RÁPIDO
• Envía por mensaje de texto o WhatsApp, con una nota lista en el idioma de tu cliente
• Pide un anticipo, registra cada pago y ve el saldo pendiente
• Convierte una cotización aprobada en factura con un toque; el anticipo pasa a la factura
• Recordatorios si una cotización lleva 3 días sin respuesta o una factura se vence
• Facturas que se repiten para clientes semanales o mensuales, con recordatorio
• Ve cuánto te deben y cuánto cobraste este mes

SABE CUÁNTO GANASTE
• Los recibos escaneados guardan tu costo; Cotiza le suma tu ganancia (15% de inicio) a lo que paga el cliente
• Reportes por mes y por año: ingresos, impuesto cobrado, costo de materiales y ganancia por trabajo
• Exporta un CSV o un PDF para tu contador en temporada de impuestos

ESCRIBE MENOS
• Escanea el recibo de la tienda y agrega los materiales a la factura
• Elige al cliente de tus Contactos
• Widgets en la pantalla de inicio y bloqueada, y Siri: "¿Cuánto me deben en Cotiza?"

EN TODOS TUS DISPOSITIVOS
Tus trabajos se sincronizan con tu iCloud privado: están en tu iPhone nuevo y en tu iPad. Nosotros nunca los vemos.

CADA VEZ MÁS RÁPIDO
Cotiza recuerda los precios que usas, así tus trabajos de siempre se llenan solos.

PRIVADO POR DISEÑO
Sin cuenta ni registro. Tus trabajos, clientes y precios se guardan en tu teléfono y en tu iCloud privado. Con Apple Intelligence, la cotización la escribe el modelo de Apple dentro del teléfono. Un enlace para firmar se borra del servidor al firmarse.

Para pintores, jardineros, limpieza, mantenimiento, techos, pisos, tablaroca, concreto, plomería, electricidad, aire acondicionado y contratistas.

COTIZA PRO
Prueba Cotiza gratis con 3 cotizaciones. Cotiza Pro te da cotizaciones ilimitadas, facturas, facturas que se repiten, anticipos y pagos parciales, firma del cliente, reportes de ganancias, tu logo en cada documento y sin la marca de Cotiza. Elige plan semanal, mensual o anual; el plan anual empieza con una prueba gratis de 3 días para nuevos suscriptores.

El pago se carga a tu cuenta de Apple al confirmar la compra. La suscripción se renueva automáticamente a menos que se cancele al menos 24 horas antes de que termine el periodo actual. La renovación se cobra dentro de las 24 horas previas al final del periodo. Puedes administrarla o cancelarla cuando quieras en la configuración de tu cuenta del App Store. La parte no usada de una prueba gratis se pierde al comprar una suscripción.

Términos de uso (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Términos de suscripción: https://cotiza.adilemree.xyz/es/terms
Política de privacidad: https://cotiza.adilemree.xyz/es/privacy
```

**What's New** (4000) — 1.1.1
```
Anticipos y pagos parciales

• Pide un anticipo en tus cotizaciones. Pon tu porcentaje de siempre una vez en Configuración. El anticipo sale en el PDF, en la página para firmar y en el mensaje a tu cliente.
• Registra cada pago: el monto, la fecha y cómo te pagó tu cliente (efectivo, cheque, Zelle, Cash App, Venmo o tarjeta).
• Las facturas muestran lo que ya te pagaron y el saldo pendiente. Un anticipo pagado en la cotización pasa a la factura.
• Cuando te pagan todo, el trabajo queda como pagado solo.
• La pantalla de inicio muestra cuánto te debe cada cliente, y los recordatorios de pago vencido dicen el saldo, no el total.
• Los reportes cuentan cada pago el día en que lo recibiste, anticipos incluidos.
• Pantalla de cotización y factura más limpia: fechas, repetición, porcentaje de anticipo, idioma y estado ahora están en Más opciones.
• Cotiza ahora también está en turco: la app, la voz y los documentos.

Registrar pagos es parte de Cotiza Pro.
```

---

## 4. Turkish

Türkiye mağazası için (App Store Connect'te dil ekle → **Turkish**). Uygulamada para birimi hâlâ dolar ($) ve
vergi ABD tarzı tek oran; metinler bu yüzden para birimi, KDV ya da e-fatura vaat etmiyor. Ödeme yöntemlerinde de
Zelle/Venmo gibi ABD'ye özgü adlar geçmiyor.

**Name** (30)
```
Cotiza: Teklif ve Fatura
```

**Subtitle** (30)
```
Ustalar için sesle teklif
```

**Promotional text** (170)
```
İşi fiyatlarıyla birlikte sesli anlat. Cotiza onu müşterinin yerinde onaylayabileceği düzgün, profesyonel bir teklife çevirir.
```

**Keywords** (100 byte; Türkçe harfler 2 bayt sayılır)
```
fiyat,keşif,boyacı,tadilat,tesisat,elektrikçi,kapora,imza,makbuz,proforma,müşteri,kâr
```

**Description** (4000)
```
İşi, müşterinin kapısından çıkmadan profesyonel bir teklif göndererek al.

Cotiza, yazmak yerine konuşmayı tercih eden ustalar ve küçük ekipler için yapıldı. İşi miktarları ve fiyatlarıyla birlikte Türkçe sesli anlat. Cotiza onu kalemlere ayırır, toplar ve işletmenin adıyla düzgün bir PDF teklif hazırlar; SMS, WhatsApp ya da e-postayla göndermeye hazır.

YAZMA, SÖYLE
"2 yatak odası boyama tanesi 350, 3 kapı takma tanesi 120 ve 8 saat işçilik saati 45. Müşteri Ayşe Yılmaz."
Cotiza her işi, miktarı, birimi ve fiyatı ayırır. Sen kontrol edersin, yanlışı tek dokunuşla düzeltir ve gönderirsin. "Tanesi 120", "metrekaresi 25", "toplam 600" ya da "iki buçuk saat" gibi günlük söyleyişleri anlar.

TÜRKÇE KONUŞ, İSTEDİĞİN DİLDE GÖNDER
Hangi dilde düşünüyorsan o dilde konuş. Her belge Türkçe, İngilizce ya da İspanyolca olabilir; müşterin teklifi okuduğu dilde alır.

İŞİ UZAKTAN BİLE BAĞLA
Müşterin telefonunda parmağıyla ya da SMS veya WhatsApp ile gönderdiğin bir bağlantıdan imzalar. Teklif onaylanır, sana bildirim gelir ve imza tarihle birlikte PDF'e basılır. Yazıcı yok, kâğıt yok.

PROFESYONEL GÖRÜN
• İşletme bilgilerin, ruhsat numaran, koşulların ve geçerlilik ya da son ödeme tarihiyle düzgün PDF teklif ve faturalar
• Yalnızca işaretlediğin kalemlere uygulanan vergi
• Müşteriye notlar: süre, kapora, nelerin dahil olduğu

PARANI DAHA ÇABUK AL
• Müşterinin dilinde hazır bir notla SMS ya da WhatsApp ile gönder
• Kapora iste, her ödemeyi kaydet ve kalan tutarı gör
• Onaylanan teklifi tek dokunuşla faturaya çevir; alınan kapora faturaya geçer
• Bir teklif 3 gün yanıtsız kalınca ya da faturanın vadesi geçince hatırlatma
• Haftalık ya da aylık müşteriler için tekrarlanan faturalar, günü gelince hatırlatmayla hazır
• Neyin yanıt beklediğini ve bu ay ne kadar tahsil ettiğini gör

NE KAZANDIĞINI BİL
• Taranan fişler maliyetini saklar; Cotiza müşterinin ödediği fiyata kâr payını (varsayılan %15) ekler
• Aylık ve yıllık raporlar: gelir, toplanan vergi, malzeme maliyeti ve iş başına kâr
• Muhasebecin için tablo (CSV) ya da PDF olarak dışa aktar

DAHA AZ YAZ
• Mağaza fişini tara, malzemeleri faturaya ekle
• Müşteriyi Kişiler'den seç
• Ana ekran ve kilit ekranı widget'ları, ve Siri: "Cotiza içinde ne kadar alacağım var"

TÜM CİHAZLARINDA
İşlerin özel iCloud'un üzerinden senkronlanır; yeni iPhone'unda ve iPad'inde de seninle. Biz hiçbir zaman göremeyiz.

HER SEFERİNDE DAHA HIZLI
Cotiza kullandığın fiyatları hatırlar; her zamanki işlerin kendiliğinden dolar.

GİZLİLİK ESASTIR
Hesap yok, kayıt yok. İşlerin, müşterilerin ve fiyatların telefonunda ve özel iCloud'unda saklanır. Apple Intelligence olan iPhone'larda teklifi Apple'ın cihaz üzerindeki modeli yazar; iş tarifin bize gönderilmez. Gönderdiğin imza bağlantısı imzalanınca sunucumuzdan silinir.

Boyacılar, bahçıvanlar, temizlikçiler, tadilat, çatı, parke, alçıpan, beton, sıhhi tesisat, elektrik ve klima ustaları ve müteahhitler için.

COTIZA PRO
Cotiza'yı 3 teklifle ücretsiz dene. Cotiza Pro ile sınırsız teklif, faturalar, tekrarlanan faturalar, kapora ve kısmi ödemeler, müşteri imzası, kâr raporları, her belgede kendi logon ve Cotiza markası olmadan belgeler. Haftalık, aylık ya da yıllık seç; yıllık plan yeni aboneler için 3 günlük ücretsiz denemeyle başlar.

Ödeme, satın almayı onayladığında Apple Hesabı'ndan alınır. Abonelik, mevcut dönemin bitiminden en az 24 saat önce iptal edilmezse otomatik olarak yenilenir. Yenileme ücreti dönem bitmeden önceki 24 saat içinde alınır. Aboneliğini istediğin zaman App Store hesap ayarlarından yönetebilir ya da iptal edebilirsin. Abonelik satın aldığında ücretsiz denemenin kullanılmayan kısmı geçersiz olur.

Kullanım Koşulları (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Abonelik koşulları: https://cotiza.adilemree.xyz/tr/terms
Gizlilik Politikası: https://cotiza.adilemree.xyz/tr/privacy
```

**What's New** (4000) — 1.1.1
```
Cotiza artık Türkçe

• Uygulamanın tamamı Türkçe: ekranlar, widget'lar ve Siri.
• İşi Türkçe sesli anlat: "tanesi 120", "metrekaresi 25", "toplam 600", "iki buçuk saat" gibi söyleyişleri anlar.
• Belge dili olarak Türkçe: PDF, müşteriye giden mesaj, imza sayfası ve kâr raporu.

Kapora ve kısmi ödemeler

• Tekliflerinde kapora iste. Her zamanki yüzdeni bir kez Ayarlar'da gir. Kapora PDF'te, imza sayfasında ve müşteriye giden mesajda görünür.
• Her ödemeyi kaydet: tutarı, tarihi ve müşterinin nasıl ödediğini (nakit, çek, kart ya da diğer).
• Faturalar ödenenleri ve kalan tutarı gösterir. Teklifte alınan kapora faturaya geçer.
• Her şey ödendiğinde iş kendiliğinden ödendi olarak işaretlenir.
• Ana ekran her müşterinin kalan borcunu gösterir; vadesi geçen hatırlatmaları toplamı değil kalan tutarı söyler.
• Raporlar, kaporalar dahil her ödemeyi alındığı gün sayar.
• Daha sade teklif ve fatura ekranı: tarihler, tekrar, kapora yüzdesi, dil ve durum artık Diğer ayarlar altında.

Ödeme kaydetmek Cotiza Pro'ya dahildir.
```

---

## 5. Abonelikler (Monetization → Subscriptions)

**Subscription group:** reference name `Cotiza Pro`

| | English (U.S.) | Spanish (Mexico) | Turkish |
| --- | --- | --- | --- |
| Group display name | Cotiza Pro | Cotiza Pro | Cotiza Pro |

| Product ID | Reference name | Süre | Fiyat (öneri) | Intro offer |
| --- | --- | --- | --- | --- |
| `com.cotiza.app.pro.yearly` | Pro Yearly | 1 Year | $99.99 | Free trial, **3 days**, new subscribers |
| `com.cotiza.app.pro.monthly` | Pro Monthly | 1 Month | $14.99 | — |
| `com.cotiza.app.pro.weekly` | Pro Weekly | 1 Week | $4.99 | — |

Üçü aynı abonelik grubunda olmalı (kullanıcı planlar arasında geçiş yapabilsin). Sıralama (level): Yearly 1, Monthly 2, Weekly 3.

Product ID'ler kodla birebir aynı olmak zorunda.

| Product | Display name (EN, 30) | Description (EN, 45) | Display name (ES, 30) | Description (ES, 45) |
| --- | --- | --- | --- | --- |
| Yearly | Cotiza Pro Yearly | Unlimited estimates, invoices and your logo | Cotiza Pro Anual | Cotizaciones ilimitadas, facturas y tu logo |
| Monthly | Cotiza Pro Monthly | Unlimited estimates, invoices and your logo | Cotiza Pro Mensual | Cotizaciones ilimitadas, facturas y tu logo |
| Weekly | Cotiza Pro Weekly | Unlimited estimates, invoices and your logo | Cotiza Pro Semanal | Cotizaciones ilimitadas, facturas y tu logo |

Turkish:

| Product | Display name (TR, 30) | Description (TR, 45) |
| --- | --- | --- |
| Yearly | Cotiza Pro Yıllık | Sınırsız teklif, fatura ve kendi logon |
| Monthly | Cotiza Pro Aylık | Sınırsız teklif, fatura ve kendi logon |
| Weekly | Cotiza Pro Haftalık | Sınırsız teklif, fatura ve kendi logon |

**Review screenshot** (her ürün için istenir): uygulamadaki Pro ekranının ekran görüntüsü.

Her iki ürünü sürüm sayfasındaki **In-App Purchases and Subscriptions** bölümünden ilk sürüme ekle;
eklemezsen inceleme ürünleri göremez ve reddeder.

---

## 6. App Review Information → Notes

```
No account or sign-in is needed.

HOW TO TEST
1. Tap "Get started", enter any business name, choose a trade and tap Continue.
2. The Cotiza Pro offer appears once; close it with the X to stay on the free plan.
3. Tap "New estimate". Either tap the microphone and describe a job, or type it, for example:
   "Paint two bedrooms at 350 each, install 3 doors at 120 each and 8 hours of labor at 45 an hour. Client Maria Lopez."
4. Tap "Create estimate". Line items, quantities and prices are filled in. Tap "Preview and send" to see the PDF.

SUBSCRIPTION
The free plan allows 3 estimates. Creating a 4th, converting an estimate to an invoice, getting a client signature ("Get client signature" at the bottom of an estimate), recording a payment ("Record a payment" under Payments in an estimate or invoice), opening Reports (chart button on the home screen) or adding a logo opens the Cotiza Pro screen, where the yearly (with a 3-day free trial), monthly and weekly plans can be bought with a sandbox account. "Restore purchases" is on the same screen.

AI AND PRIVACY
On devices with Apple Intelligence, the estimate is generated with Apple's on-device Foundation Models framework. On other devices the app uses a built-in parser, so the full flow works on any supported iPhone. No data is sent to our servers; the app has no server and no analytics. Data syncs between the user's own devices through their private iCloud database (CloudKit), which we cannot access.

PERMISSIONS
Microphone and Speech Recognition are requested only when the user taps the microphone, to turn the spoken job description into text. Typing works without them.
Camera is requested only when the user scans a store receipt; receipt text is read on the device. A photo can be chosen instead.
Notifications are requested when the first document is sent, for follow-up and past-due reminders.
SIGNING LINKS (Pro): open an estimate, tap "Send a signing link" under Client approval and share the text. Opening the link in any browser shows the estimate; signing it there approves the estimate in the app (the app checks when it comes to the foreground, or tap "Check now"). They are scheduled on the device.
"Choose from Contacts" uses the system contact picker, so the app never gets access to the whole address book.
```

Contact information: adın, telefonun ve e-postan (yalnızca Apple görür). Kullanıcıya görünen destek
adresi: `destek@adilemree.xyz`.

---

## 7. App Privacy

**Data collection:** `Yes, we collect data from this app` — yalnızca imza linki özelliği için.

Toplanan veri türleri (hepsi için: **App Functionality**, **Not linked to the user's identity**,
**Not used for tracking**):

| Kategori | Ne | Neden |
| --- | --- | --- |
| Contact Info → Name | Müşterinin adı, imzalayanın yazdığı ad | İmza sayfasında göstermek ve onayı kaydetmek |
| User Content → Other User Content | Teklifin PDF'i ve içeriği, imza görseli | Müşterinin teklifi görüp imzalaması |
| Identifiers / Diagnostics | — | Toplanmıyor |

İmzalayanın IP adresi ve tarayıcısı onay kaydı olarak saklanıyor (Apple'ın kategorilerinde ayrı bir
seçenek yok; gizlilik politikasında yazıyor). Kullanıcı hesabı yok; kayıtlar uygulama imzayı alınca, en geç
30 günde siliniyor ve yedeklenmiyor.

Gerisi değişmedi: işler, müşteriler ve fiyatlar cihazda ve kullanıcının kendi iCloud'unda (CloudKit private
database) duruyor; geliştirici bunlara erişemiyor. Satın alma Apple üzerinden. Analitik ve çökme raporlama
SDK'sı yok; eklersen bu cevabı güncelle.

---

## 8. Ekran görüntüleri

Hazır dosyalar `AppStore/screenshot-kit/out/<dil>/<cihaz>/` içinde, App Store Connect'in kabul ettiği
boyutlarda. Sıra dosya adındaki numaradır (01–06). `en` → English (U.S.), `es` → Spanish (Mexico).
Tasarım: sade turuncu zemin, yalnız büyük başlık (vurgu kelimeler koyu kahve), çerçeveli cihaz.

| Klasör | App Store Connect'teki alan | Boyut |
| --- | --- | --- |
| `iphone69` | iPhone 6.9" Display | 1320 × 2868 |
| `iphone63` | iPhone 6.3" Display | 1206 × 2622 |
| `ipad13` | iPad 13" Display | 2064 × 2752 |
| `duo-outer` | iPhone Duo, katlı (dış ekran) | 1398 × 2034 |
| `duo-inner-land` | iPhone Duo, açık (iç ekran, yatay) | 2853 × 2007 |

| # | Ekran | EN başlık | ES başlık |
| --- | --- | --- | --- |
| 01 | Sesle iş tarifi | Say the job. Get the estimate. | Di el trabajo. Recibe la cotización. |
| 02 | Editör, kalemler dolu | Prices and quantities, filled in for you | Precios y cantidades, listos para ti |
| 03 | PDF önizleme | A professional estimate in one tap | Un PDF profesional con un toque |
| 04 | Müşteri imzası | Your client signs on your phone | Tu cliente firma en tu teléfono |
| 05 | Ana ekran | Know who owes you | Sabes quién te debe |
| 06 | Kâr raporu | See what you really made | Mira cuánto ganaste de verdad |

Abonelik ürünlerinin "Review screenshot" alanı için Pro ekranının çerçevesiz hali:
`AppStore/screenshots/raw/iPhone-18-Pro/en/7-paywall.png`.

Yeniden üretmek için (örnek veriyle, DEBUG derlemesinde). Önce ham ekranlar:

```bash
Tools/screenshots.sh
```

Sonra AppStoreScreenshotKit ile slaytlar (metinler ve renkler `AppStore/screenshot-kit/config.py` içinde):

```bash
AppStore/screenshot-kit/link_raw.sh
```

```bash
python3 ~/Developer/AppStoreScreenshotKit/compose.py AppStore/screenshot-kit/config.py
```

Ham ekranlar `-CotizaScreen <sahne>` argümanıyla açılır (`Cotiza/App/ScreenshotMode.swift`). Simülatörler:
"Cotiza Shots iPhone 18 Pro", "Cotiza Shots iPad Pro 13" ve iOS 27.2'deki "iPhone Duo".
