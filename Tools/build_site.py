"""Builds the Cotiza website (English at /, Spanish at /es/) into AppStore/site.

    python3 Tools/build_site.py

Styled like the other app sites on the server (budgett): the same style.css, one sticky header,
plain cards, no JavaScript. Deploy with Tools/deploy_site.sh.
"""
import hashlib
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent / "AppStore" / "site"
DOMAIN = "https://cotiza.adilemree.xyz"
EMAIL = "destek@adilemree.xyz"
UPDATED = {"en": "November 12, 2026", "es": "12 de noviembre de 2026"}
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
# Cache-busting: assets are cached for a week, so the stylesheet URL changes with its content.
CSS = "/assets/style.css?v=" + hashlib.sha256((SITE / "assets" / "style.css").read_bytes()).hexdigest()[:10]

T = {
    "en": dict(privacy="Privacy", support="Support", terms="Terms", other="Español", other_href="/es/",
               home="/", updated="Last updated", footer="Cotiza"),
    "es": dict(privacy="Privacidad", support="Soporte", terms="Términos", other="English", other_href="/",
               home="/es/", updated="Última actualización", footer="Cotiza"),
}


def page(lang: str, path: str, title: str, description: str, body: str, doc: bool = True) -> None:
    t = T[lang]
    prefix = "" if lang == "en" else "/es"
    alt_lang = "es" if lang == "en" else "en"
    # The same page in the other language: /privacy <-> /es/privacy, / <-> /es/
    if lang == "en":
        alt_path = "/es/" if path == "/" else "/es" + path
    else:
        alt_path = path
    html = f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0b0b0c" media="(prefers-color-scheme: dark)">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:type" content="website">
<meta property="og:url" content="{DOMAIN}{prefix}{path if path != '/' else '/'}">
<link rel="alternate" hreflang="{alt_lang}" href="{DOMAIN}{alt_path}">
<link rel="icon" href="/assets/icon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{CSS}">
</head>
<body>

<header class="site">
  <div class="wrap">
    <a class="brand" href="{t['home']}" aria-label="Cotiza"><img src="/assets/icon.svg" alt=""><span>Cotiza</span></a>
    <nav class="top">
      <a href="{prefix}/privacy">{t['privacy']}</a>
      <a href="{prefix}/support">{t['support']}</a>
      <a href="{prefix}/terms">{t['terms']}</a>
      <a class="lang" href="{alt_path}" hreflang="{alt_lang}">{t['other']}</a>
    </nav>
  </div>
</header>

<main class="wrap{' doc' if doc else ''}">
{body.strip()}
</main>

<footer class="site">
  <div class="wrap">
    <span>© 2026 Adil Emre · Cotiza</span>
    <span>
      <a href="{prefix}/privacy">{t['privacy']}</a> ·
      <a href="{prefix}/support">{t['support']}</a> ·
      <a href="{prefix}/terms">{t['terms']}</a> ·
      <a href="mailto:{EMAIL}">{EMAIL}</a>
    </span>
  </div>
</footer>

</body>
</html>
"""
    out = SITE / (lang if lang != "en" else "") / ("index.html" if path == "/" else path.strip("/") + ".html")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html)


# ---------------------------------------------------------------- English

page("en", "/", "Cotiza — Estimates by Voice",
     "Describe the job out loud in Spanish or English. Cotiza turns it into a professional estimate your client can approve on the spot. No account, no tracking.",
     f"""
  <div class="hero">
    <img class="icon" src="/assets/icon.svg" alt="Cotiza app icon">
    <h1>Say the job.<br>Send the estimate.</h1>
    <p class="lede">Describe the work out loud, in Spanish or English, with your prices. Cotiza writes a clean, professional estimate your client can approve before you leave.</p>
    <a class="cta" href="/support">Support &amp; FAQ</a>
    <a class="cta ghost" href="/privacy">Privacy</a>
    <p class="note">iPhone · iOS 26 or later · Free to try</p>
  </div>

  <section>
    <div class="quote">
      <div class="who">You say</div>
      “Paint two bedrooms at 350 each, install 3 doors at 120 each and 8 hours of labor at 45 an hour. Client Maria Lopez.”
    </div>
    <div class="shot sample"><img src="/assets/sample-estimate.png" alt="A sample estimate PDF made with Cotiza" loading="lazy"></div>
    <p class="note" style="text-align:center">Cotiza makes the estimate</p>
  </section>

  <section>
    <h2>Built for the job site</h2>
    <p class="sub">For painters, landscapers, cleaners, handymen, roofers and every contractor in between.</p>
    <div class="grid">
      <div class="card"><h3>Talk, don't type</h3><p>Tasks, quantities, units and prices become line items. Fix anything with a tap.</p></div>
      <div class="card"><h3>Speak Spanish, send English</h3><p>Talk in the language you think in. Your client gets the estimate in the language they read.</p></div>
      <div class="card"><h3>A PDF that looks the part</h3><p>Your business name, license number and terms. Text it, or send a link your client signs from anywhere.</p></div>
      <div class="card"><h3>Estimate to invoice</h3><p>Turn an approved estimate into an invoice in one tap, then mark it paid.</p></div>
      <div class="card"><h3>Remembers your prices</h3><p>The prices you use most fill in by themselves next time.</p></div>
      <div class="card"><h3>Siri ready</h3><p>“New estimate in Cotiza” opens the recorder straight away.</p></div>
    </div>
  </section>

  <section class="banner">
    <h2>Your jobs stay yours.</h2>
    <p>No account, no sign-up, no ads, no tracking. Your clients, prices and estimates are stored on your iPhone and in your own iCloud. Only an estimate you send for signing passes through our server, and it's deleted once it's signed.</p>
  </section>
""", doc=False)

page("en", "/privacy", "Privacy Policy — Cotiza",
     "Cotiza keeps your jobs, clients and prices on your iPhone and in your own iCloud. Only an estimate you send for signing stays on our server, and only until it's signed.",
     f"""
  <h1>Privacy Policy</h1>
  <p class="updated">{T['en']['updated']}: {UPDATED['en']}</p>
  <p><strong>Cotiza does not sell or share personal data, and has no ads, analytics or user accounts.</strong> Your jobs, clients and prices stay on your iPhone and in your own iCloud. The one exception is a signing link you choose to send: that estimate is kept on our server only until your client signs it (section 8).</p>

  <h2>1. Who we are</h2>
  <p>Cotiza is made by Adil Emre Karayürek, an individual developer in Türkiye.<br>
  Contact: <a href="mailto:{EMAIL}">{EMAIL}</a></p>

  <h2>2. Data stored on your iPhone</h2>
  <p>The following is kept only in the app's storage on your device, to make the app work:</p>
  <ul>
    <li>Your business details and, if you add one, your logo</li>
    <li>Clients you add: name, phone, email and job address</li>
    <li>Estimates, invoices, line items (including lines added from a receipt), notes, dates and saved prices</li>
    <li>Signatures your clients draw on your phone, with the name they enter and the date</li>
    <li>App settings</li>
  </ul>
  <p>This data never reaches us. If you're signed in to iCloud, it is also kept in your private iCloud database so it appears on your other iPhones and iPads with the same Apple Account. That database belongs to your Apple Account; we cannot read it. Data is also included in your device backups according to your own settings.</p>

  <h2>3. Voice input</h2>
  <p>When you tap the microphone, Cotiza uses Apple's Speech framework to turn what you say into text. When your iPhone supports on-device recognition for your language, this happens entirely on the device. Otherwise Apple may process the audio on its servers under <a href="https://www.apple.com/legal/privacy/">Apple's Privacy Policy</a>. Cotiza does not record, store or send your audio.</p>
  <p>Microphone and speech recognition permission is asked only when you first tap the microphone. You can always type the job instead.</p>

  <h2>4. How the estimate is written</h2>
  <p>On iPhones with Apple Intelligence, the estimate is written by Apple's on-device language model. On other iPhones Cotiza uses a built-in parser. In both cases your job description stays on the device and is not sent to us.</p>

  <h2>5. Photos and camera</h2>
  <p>If you choose a logo, only the image you pick is copied into the app.</p>
  <p>To scan a store receipt, you take a photo with the camera or pick one. Cotiza reads the text on your iPhone to find items and prices. The photo itself is not saved: only the lines you choose to add are kept. Camera permission is asked only the first time you scan with the camera. Cotiza does not read your photo library.</p>

  <h2>6. Contacts</h2>
  <p>When you tap “Choose from Contacts”, iOS shows its own contact picker. Cotiza receives only the contact you pick and copies its name, phone, email and address into that client. It does not get access to your other contacts and does not ask for Contacts permission.</p>

  <h2>7. Sending documents</h2>
  <p>When you send an estimate or invoice by text message, Cotiza fills in your client's number, a short note and the PDF, and you review and send it in Messages. For WhatsApp, email or other apps, you choose the app and the recipient in the iOS share sheet. Cotiza never sends anything by itself; from then on the app you choose handles it.</p>

  <h2>8. Signing links</h2>
  <p>When you tap “Send a signing link”, Cotiza uploads that one estimate to our server at cotiza.adilemree.xyz so your client can open it in a browser: the estimate's PDF and what the page shows (your business name and contact details, the client's name, the items, prices and terms). When your client signs, the server also stores the name they type, their signature, the time, and their IP address and browser, as a record of the approval.</p>
  <p>The link is private: it is a long random address, it is not indexed by search engines, and only the device that created it can read the result. As soon as Cotiza collects the signature, it deletes the request from the server. Anything not collected is deleted automatically 30 days after it was sent or signed. “Cancel the link” deletes it right away. These records are not backed up, sold or shared, and are used only to show the estimate and return the signature to you.</p>

  <h2>9. Reminders</h2>
  <p>If you allow notifications, Cotiza schedules reminders on your iPhone: when an estimate has had no answer for a few days and when an invoice is past due. They are created on the device; there is no notification server. You can turn them off in Cotiza's Settings or in iOS Settings.</p>

  <h2>10. Widgets, Siri and Spotlight</h2>
  <p>The Cotiza widget shows the totals the app saves in a space shared only with its own widget on your iPhone. Your estimates and invoices are added to your iPhone's search index so you can find them in Spotlight and ask Siri about them. That index stays on your device and is managed by iOS.</p>

  <h2>11. Purchases</h2>
  <p>Cotiza Pro subscriptions are sold and processed by Apple. We never receive your payment details.</p>

  <h2>12. Analytics, ads and third parties</h2>
  <p>Cotiza contains <strong>no advertising, analytics, crash-reporting or tracking SDKs</strong>. No usage data is collected and nothing is shared with or sold to third parties.</p>

  <h2>13. Deleting your data</h2>
  <ul>
    <li>Delete any estimate, invoice, client or saved price inside the app. Deleting a document, or tapping “Remove signature”, also deletes its signature.</li>
    <li>Deleting the app removes all of its data from the device, including what the widget shows and what Spotlight finds. A copy stays in your private iCloud until you delete it in iOS Settings › your name › iCloud › Manage storage › Cotiza.</li>
    <li>We hold no copy, so there is nothing to request from us.</li>
  </ul>

  <h2>14. Children</h2>
  <p>Cotiza is a business tool, is not directed at children and is rated 4+ on the App Store.</p>

  <h2>15. Your rights</h2>
  <p>Depending on where you live (for example under the CCPA in California, the GDPR in Europe or the KVKK in Türkiye), you may have the right to know, access, correct or delete your personal data. Your data is on your device and in your iCloud, so deleting it there is enough; signing-link records delete themselves as described in section 8. You can still contact us at <a href="mailto:{EMAIL}">{EMAIL}</a>; we reply within 30 days.</p>

  <h2>16. Changes</h2>
  <p>If this policy changes, the new version will be posted on this page with a new date.</p>
""")

page("en", "/support", "Support — Cotiza",
     "Help with Cotiza: voice input, prices, subscriptions and your data.",
     f"""
  <h1>Support</h1>
  <p class="muted">Answers to common questions. Still stuck? Write to us.</p>

  <details><summary>The microphone doesn't work</summary>
    <p>Open the iPhone Settings app, tap Apps › Cotiza and turn on Microphone and Speech Recognition. You can also type the job instead.</p></details>
  <details><summary>A price or quantity came out wrong</summary>
    <p>Tap the line in the estimate to change its description, quantity, unit or price. Lines Cotiza couldn't price are marked “Add price”, and Cotiza never makes up a price you didn't say.</p></details>
  <details><summary>How do I send the estimate to my client?</summary>
    <p>Tap “Preview and send”. “Text message” opens Messages with your client's number, a short note in their language and the PDF. “WhatsApp” hands the PDF and the note to WhatsApp, where you pick the chat. “Email or other apps” opens the share sheet.</p></details>
  <details><summary>How does my client sign the estimate?</summary>
    <p>Open the estimate (Cotiza Pro). “Get client signature”: hand your client the phone and they sign with a finger. “Send a signing link”: send a link by text or WhatsApp; your client opens it, reviews the estimate and signs in the browser, and you get a notification. Either way the estimate is marked approved and the signature is printed on the PDF with the date.</p></details>
  <details><summary>How do I add materials from a store receipt?</summary>
    <p>In an estimate or invoice, tap “Scan a receipt”, then take a photo or choose one. Check the items and prices Cotiza found, untick any you don't want and tap Add. Totals, tax and payment lines are left out.</p></details>
  <details><summary>Can the estimate be in English if I speak Spanish?</summary>
    <p>Yes. Set the document language in Settings, or per estimate. On iPhones with Apple Intelligence the items are written in that language; on others, Cotiza translates them on the device when the language pack is available.</p></details>
  <details><summary>What do I get with Cotiza Pro?</summary>
    <p>Unlimited estimates, invoices, recurring invoices, client signatures, profit reports, your logo on every document and no “Made with Cotiza” footer. The free plan includes 3 estimates.</p></details>
  <details><summary>How do I cancel my subscription?</summary>
    <p>Open Settings on your iPhone, tap your name › Subscriptions › Cotiza Pro. Or in Cotiza, open Settings › Manage subscription. Cancel at least 24 hours before renewal to avoid the next charge.</p></details>
  <details><summary>I got a new phone and Pro is gone</summary>
    <p>In Cotiza, tap Go Pro › Restore purchases, signed in with the Apple Account you subscribed with.</p></details>
  <details><summary>Where is my data? How do I move it to a new phone?</summary>
    <p>On your iPhone and, if you're signed in to iCloud, in your private iCloud. Sign in to a new iPhone or an iPad with the same Apple Account and your jobs appear there. See the <a href="/privacy">privacy policy</a>.</p></details>
  <details><summary>How do I give my accountant my numbers?</summary>
    <p>Tap the chart button on the home screen (Cotiza Pro). Pick a month or a year and tap Export for a spreadsheet (CSV) or a PDF summary with revenue, sales tax, materials cost and profit.</p></details>
  <details><summary>How do recurring invoices work?</summary>
    <p>Open an invoice and set Repeat to every week, every 2 weeks or every month. On that day Cotiza makes a copy with a new number and the same items, and reminds you to send it.</p></details>

  <div class="contact">
    Email: <a href="mailto:{EMAIL}">{EMAIL}</a><br>
    <span class="muted">We usually reply within one business day. Please include your iPhone model and iOS version.</span>
  </div>
""")

page("en", "/terms", "Terms of Use — Cotiza",
     "Terms of use and subscription terms for Cotiza.",
     f"""
  <h1>Terms of Use</h1>
  <p class="updated">{T['en']['updated']}: {UPDATED['en']}</p>
  <p>Cotiza is licensed to you under Apple's <a href="{EULA}">Standard End User License Agreement</a>. The points below add to it.</p>

  <h2>Subscriptions</h2>
  <ul>
    <li>Cotiza Pro is an auto-renewing subscription, offered weekly, monthly and yearly. Prices are shown in the app before you buy.</li>
    <li>Payment is charged to your Apple Account when you confirm the purchase.</li>
    <li>The subscription renews automatically unless canceled at least 24 hours before the end of the current period. Renewal is charged within the 24 hours before the period ends.</li>
    <li>Manage or cancel anytime in your App Store account settings.</li>
    <li>Any unused part of a free trial is forfeited when you buy a subscription.</li>
    <li>Refunds are handled by Apple under its policies.</li>
  </ul>

  <h2>Your estimates</h2>
  <p>Cotiza helps you prepare estimates and invoices from what you say or type. You are responsible for checking every description, quantity, price and tax before you send a document, and for the agreements you make with your clients. Cotiza does not give legal, tax or accounting advice.</p>

  <h2>Contact</h2>
  <p><a href="mailto:{EMAIL}">{EMAIL}</a></p>
""")

# ---------------------------------------------------------------- Spanish

page("es", "/", "Cotiza — Cotizaciones por voz",
     "Describe el trabajo en voz alta, en español o en inglés. Cotiza lo convierte en una cotización profesional que tu cliente puede aprobar ahí mismo. Sin cuenta y sin rastreo.",
     f"""
  <div class="hero">
    <img class="icon" src="/assets/icon.svg" alt="Ícono de la app Cotiza">
    <h1>Di el trabajo.<br>Envía la cotización.</h1>
    <p class="lede">Describe el trabajo en voz alta, en español o en inglés, con tus precios. Cotiza escribe una cotización clara y profesional que tu cliente puede aprobar antes de que te vayas.</p>
    <a class="cta" href="/es/support">Soporte y preguntas</a>
    <a class="cta ghost" href="/es/privacy">Privacidad</a>
    <p class="note">iPhone · iOS 26 o posterior · Pruébala gratis</p>
  </div>

  <section>
    <div class="quote">
      <div class="who">Tú dices</div>
      “Pintar dos recámaras a 350 cada una, instalar 3 puertas a 120 cada una y 8 horas de mano de obra a 45 la hora. Cliente María López.”
    </div>
    <div class="shot sample"><img src="/assets/sample-estimate.png" alt="Ejemplo de cotización en PDF hecha con Cotiza" loading="lazy"></div>
    <p class="note" style="text-align:center">Cotiza arma la cotización</p>
  </section>

  <section>
    <h2>Hecha para la obra</h2>
    <p class="sub">Para pintores, jardineros, limpieza, mantenimiento, techos y todo tipo de contratista.</p>
    <div class="grid">
      <div class="card"><h3>Habla, no escribas</h3><p>Trabajos, cantidades, unidades y precios se convierten en conceptos. Corrige lo que quieras con un toque.</p></div>
      <div class="card"><h3>Habla español, envía en inglés</h3><p>Habla en el idioma en que piensas. Tu cliente recibe la cotización en el idioma que lee.</p></div>
      <div class="card"><h3>Un PDF que se ve profesional</h3><p>El nombre de tu negocio, tu licencia y tus términos. Mándalo por mensaje o envía un enlace que tu cliente firma desde donde esté.</p></div>
      <div class="card"><h3>De cotización a factura</h3><p>Convierte una cotización aprobada en factura con un toque y márcala como pagada.</p></div>
      <div class="card"><h3>Recuerda tus precios</h3><p>Los precios que más usas se llenan solos la próxima vez.</p></div>
      <div class="card"><h3>Lista para Siri</h3><p>“Nueva cotización en Cotiza” abre la grabadora al instante.</p></div>
    </div>
  </section>

  <section class="banner">
    <h2>Tus trabajos son solo tuyos.</h2>
    <p>Sin cuenta, sin registro, sin anuncios y sin rastreo. Tus clientes, precios y cotizaciones se guardan en tu iPhone y en tu propio iCloud. Solo una cotización que envías para firmar pasa por nuestro servidor, y se borra al firmarse.</p>
  </section>
""", doc=False)

page("es", "/privacy", "Política de privacidad — Cotiza",
     "Cotiza guarda tus trabajos, clientes y precios en tu iPhone y en tu propio iCloud. Solo una cotización que envías para firmar queda en nuestro servidor, y solo hasta que se firma.",
     f"""
  <h1>Política de privacidad</h1>
  <p class="updated">{T['es']['updated']}: {UPDATED['es']}</p>
  <p><strong>Cotiza no vende ni comparte datos personales, y no tiene anuncios, analíticas ni cuentas de usuario.</strong> Tus trabajos, clientes y precios se quedan en tu iPhone y en tu propio iCloud. La única excepción es un enlace para firmar que tú decides enviar: esa cotización se guarda en nuestro servidor solo hasta que tu cliente la firma (sección 8).</p>

  <h2>1. Quiénes somos</h2>
  <p>Cotiza es una app de Adil Emre Karayürek, desarrollador independiente en Türkiye.<br>
  Contacto: <a href="mailto:{EMAIL}">{EMAIL}</a></p>

  <h2>2. Datos guardados en tu iPhone</h2>
  <p>Lo siguiente se guarda solo en el almacenamiento de la app en tu teléfono, para que la app funcione:</p>
  <ul>
    <li>Los datos de tu negocio y, si lo agregas, tu logo</li>
    <li>Los clientes que agregues: nombre, teléfono, correo y dirección del trabajo</li>
    <li>Cotizaciones, facturas, conceptos (incluidos los que agregues desde un recibo), notas, fechas y precios guardados</li>
    <li>Las firmas que tus clientes hacen en tu teléfono, con el nombre que escriben y la fecha</li>
    <li>La configuración de la app</li>
  </ul>
  <p>Estos datos nunca nos llegan. Si tienes sesión iniciada en iCloud, también se guardan en tu base de datos privada de iCloud para que aparezcan en tus otros iPhone y iPad con la misma cuenta de Apple. Esa base de datos es de tu cuenta de Apple; nosotros no podemos leerla. Los datos también se incluyen en los respaldos de tu teléfono según tu configuración.</p>

  <h2>3. Voz</h2>
  <p>Cuando tocas el micrófono, Cotiza usa el reconocimiento de voz de Apple para convertir lo que dices en texto. Si tu iPhone puede hacerlo sin conexión en tu idioma, todo ocurre en el teléfono. Si no, Apple puede procesar el audio en sus servidores según la <a href="https://www.apple.com/legal/privacy/es/">Política de privacidad de Apple</a>. Cotiza no graba, guarda ni envía tu audio.</p>
  <p>El permiso de micrófono y reconocimiento de voz se pide solo la primera vez que tocas el micrófono. Siempre puedes escribir el trabajo.</p>

  <h2>4. Cómo se escribe la cotización</h2>
  <p>En iPhone con Apple Intelligence, la cotización la escribe el modelo de lenguaje de Apple dentro del teléfono. En otros iPhone, Cotiza usa un analizador integrado. En ambos casos tu descripción del trabajo se queda en el teléfono y no se nos envía.</p>

  <h2>5. Fotos y cámara</h2>
  <p>Si eliges un logo, solo se copia a la app la imagen que seleccionas.</p>
  <p>Para escanear un recibo de la tienda, tomas una foto con la cámara o eliges una. Cotiza lee el texto en tu iPhone para encontrar los artículos y precios. La foto no se guarda: solo se conservan los conceptos que eliges agregar. El permiso de cámara se pide solo la primera vez que escaneas con la cámara. Cotiza no lee tu fototeca.</p>

  <h2>6. Contactos</h2>
  <p>Cuando tocas “Elegir de Contactos”, iOS muestra su propio selector de contactos. Cotiza recibe solo el contacto que eliges y copia su nombre, teléfono, correo y dirección a ese cliente. No tiene acceso a tus demás contactos y no pide permiso de Contactos.</p>

  <h2>7. Documentos que envías</h2>
  <p>Cuando envías una cotización o factura por mensaje de texto, Cotiza llena el número de tu cliente, una nota corta y el PDF, y tú lo revisas y lo envías en Mensajes. Para WhatsApp, correo u otras apps, eliges la app y el destinatario en el menú de compartir de iOS. Cotiza nunca envía nada por su cuenta; desde ahí, la app que elijas se encarga.</p>

  <h2>8. Enlaces para firmar</h2>
  <p>Cuando tocas “Enviar enlace para firmar”, Cotiza sube esa cotización a nuestro servidor en cotiza.adilemree.xyz para que tu cliente la abra en el navegador: el PDF y lo que muestra la página (el nombre y los datos de contacto de tu negocio, el nombre del cliente, los conceptos, los precios y los términos). Cuando tu cliente firma, el servidor también guarda el nombre que escribe, su firma, la hora, y su dirección IP y navegador, como constancia de la aprobación.</p>
  <p>El enlace es privado: es una dirección larga y aleatoria, los buscadores no la indexan y solo el dispositivo que lo creó puede leer el resultado. En cuanto Cotiza recibe la firma, borra la solicitud del servidor. Lo que no se recibe se borra solo 30 días después de enviarse o firmarse. “Cancelar el enlace” lo borra de inmediato. Estos datos no se respaldan, no se venden ni se comparten, y solo se usan para mostrar la cotización y devolverte la firma.</p>

  <h2>9. Recordatorios</h2>
  <p>Si permites las notificaciones, Cotiza programa recordatorios en tu iPhone: cuando una cotización lleva unos días sin respuesta y cuando una factura está vencida. Se crean en el teléfono; no hay un servidor de notificaciones. Puedes apagarlos en los Ajustes de Cotiza o en los Ajustes de iOS.</p>

  <h2>10. Widgets, Siri y Spotlight</h2>
  <p>El widget de Cotiza muestra los totales que la app guarda en un espacio compartido solo con su propio widget en tu iPhone. Tus cotizaciones y facturas se agregan al índice de búsqueda de tu iPhone para que las encuentres en Spotlight y le preguntes a Siri. Ese índice se queda en tu teléfono y lo administra iOS.</p>

  <h2>11. Compras</h2>
  <p>Las suscripciones a Cotiza Pro las vende y procesa Apple. Nunca recibimos tus datos de pago.</p>

  <h2>12. Analíticas, anuncios y terceros</h2>
  <p>Cotiza <strong>no incluye anuncios, analíticas, reportes de fallos ni SDK de rastreo</strong>. No se recopilan datos de uso y nada se comparte ni se vende a terceros.</p>

  <h2>13. Borrar tus datos</h2>
  <ul>
    <li>Borra cualquier cotización, factura, cliente o precio guardado dentro de la app. Al borrar un documento, o al tocar “Quitar firma”, también se borra su firma.</li>
    <li>Al eliminar la app se borran todos sus datos del teléfono, incluido lo que muestra el widget y lo que encuentra Spotlight. Queda una copia en tu iCloud privado hasta que la borres en Ajustes de iOS › tu nombre › iCloud › Administrar almacenamiento › Cotiza.</li>
    <li>No guardamos ninguna copia, así que no hace falta pedirnos nada.</li>
  </ul>

  <h2>14. Menores</h2>
  <p>Cotiza es una herramienta de trabajo, no está dirigida a menores y tiene clasificación 4+ en el App Store.</p>

  <h2>15. Tus derechos</h2>
  <p>Según dónde vivas (por ejemplo, la CCPA en California, el RGPD en Europa o la KVKK en Türkiye), puedes tener derecho a conocer, acceder, corregir o borrar tus datos personales. Tus datos están en tu teléfono y en tu iCloud, así que basta con borrarlos ahí; los enlaces para firmar se borran solos como se explica en la sección 8. Aun así puedes escribirnos a <a href="mailto:{EMAIL}">{EMAIL}</a>; respondemos en un plazo de 30 días.</p>

  <h2>16. Cambios</h2>
  <p>Si esta política cambia, la nueva versión se publicará en esta página con una nueva fecha.</p>
""")

page("es", "/support", "Soporte — Cotiza",
     "Ayuda con Cotiza: voz, precios, suscripciones y tus datos.",
     f"""
  <h1>Soporte</h1>
  <p class="muted">Respuestas a las preguntas más comunes. ¿Sigues con dudas? Escríbenos.</p>

  <details><summary>El micrófono no funciona</summary>
    <p>Abre Ajustes en tu iPhone, toca Apps › Cotiza y activa Micrófono y Reconocimiento de voz. También puedes escribir el trabajo.</p></details>
  <details><summary>Un precio o una cantidad salió mal</summary>
    <p>Toca el concepto en la cotización para cambiar la descripción, la cantidad, la unidad o el precio. Los conceptos sin precio dicen “Poner precio”; Cotiza nunca inventa un precio que no dijiste.</p></details>
  <details><summary>¿Cómo le mando la cotización a mi cliente?</summary>
    <p>Toca “Ver y enviar”. “Mensaje de texto” abre Mensajes con el número de tu cliente, una nota corta en su idioma y el PDF. “WhatsApp” pasa el PDF y la nota a WhatsApp, donde eliges el chat. “Correo u otras apps” abre el menú de compartir.</p></details>
  <details><summary>¿Cómo firma mi cliente la cotización?</summary>
    <p>Abre la cotización (Cotiza Pro). “Pedir firma del cliente”: pásale el teléfono y firma con el dedo. “Enviar enlace para firmar”: mándale un enlace por mensaje o WhatsApp; tu cliente lo abre, revisa la cotización y firma en el navegador, y tú recibes una notificación. En los dos casos la cotización queda aprobada y la firma aparece en el PDF con la fecha.</p></details>
  <details><summary>¿Cómo agrego materiales desde un recibo?</summary>
    <p>En una cotización o factura, toca “Escanear un recibo” y luego toma una foto o elige una. Revisa los artículos y precios que encontró Cotiza, quita los que no quieras y toca Agregar. Se omiten totales, impuestos y pagos.</p></details>
  <details><summary>¿Puede salir en inglés si hablo en español?</summary>
    <p>Sí. Elige el idioma del documento en Ajustes o en cada cotización. En iPhone con Apple Intelligence los conceptos se escriben en ese idioma; en otros, Cotiza los traduce en el teléfono cuando el paquete de idioma está disponible.</p></details>
  <details><summary>¿Qué incluye Cotiza Pro?</summary>
    <p>Cotizaciones ilimitadas, facturas, facturas que se repiten, firma del cliente, reportes de ganancias, tu logo en cada documento y sin el pie “Creado con Cotiza”. El plan gratis incluye 3 cotizaciones.</p></details>
  <details><summary>¿Cómo cancelo mi suscripción?</summary>
    <p>Abre Ajustes en tu iPhone, toca tu nombre › Suscripciones › Cotiza Pro. O en Cotiza, abre Ajustes › Administrar suscripción. Cancela al menos 24 horas antes de la renovación para evitar el siguiente cobro.</p></details>
  <details><summary>Cambié de teléfono y no aparece Pro</summary>
    <p>En Cotiza, toca Hazte Pro › Restaurar compras, con la misma cuenta de Apple con la que te suscribiste.</p></details>
  <details><summary>¿Dónde están mis datos? ¿Cómo los paso a otro teléfono?</summary>
    <p>En tu iPhone y, si tienes sesión iniciada en iCloud, en tu iCloud privado. Inicia sesión con la misma cuenta de Apple en un iPhone nuevo o en un iPad y tus trabajos aparecen ahí. Consulta la <a href="/es/privacy">política de privacidad</a>.</p></details>
  <details><summary>¿Cómo le paso mis números a mi contador?</summary>
    <p>Toca el botón de gráfica en la pantalla principal (Cotiza Pro). Elige un mes o un año y toca Exportar para obtener una hoja de cálculo (CSV) o un resumen en PDF con ingresos, impuesto, costo de materiales y ganancia.</p></details>
  <details><summary>¿Cómo funcionan las facturas que se repiten?</summary>
    <p>Abre una factura y en Repetir elige cada semana, cada 2 semanas o cada mes. Ese día Cotiza hace una copia con un número nuevo y los mismos conceptos, y te recuerda enviarla.</p></details>

  <div class="contact">
    Correo: <a href="mailto:{EMAIL}">{EMAIL}</a><br>
    <span class="muted">Normalmente respondemos en un día hábil. Incluye el modelo de tu iPhone y la versión de iOS.</span>
  </div>
""")

page("es", "/terms", "Términos de uso — Cotiza",
     "Términos de uso y de suscripción de Cotiza.",
     f"""
  <h1>Términos de uso</h1>
  <p class="updated">{T['es']['updated']}: {UPDATED['es']}</p>
  <p>Cotiza se te otorga bajo el <a href="{EULA}">Contrato de licencia de usuario final estándar</a> de Apple. Los puntos siguientes lo complementan.</p>

  <h2>Suscripciones</h2>
  <ul>
    <li>Cotiza Pro es una suscripción de renovación automática, semanal, mensual o anual. Los precios se muestran en la app antes de comprar.</li>
    <li>El pago se carga a tu cuenta de Apple al confirmar la compra.</li>
    <li>La suscripción se renueva automáticamente a menos que se cancele al menos 24 horas antes de que termine el periodo. La renovación se cobra dentro de las 24 horas previas al final del periodo.</li>
    <li>Adminístrala o cancélala cuando quieras en la configuración de tu cuenta del App Store.</li>
    <li>La parte no usada de una prueba gratis se pierde al comprar una suscripción.</li>
    <li>Los reembolsos los gestiona Apple según sus políticas.</li>
  </ul>

  <h2>Tus cotizaciones</h2>
  <p>Cotiza te ayuda a preparar cotizaciones y facturas a partir de lo que dices o escribes. Eres responsable de revisar cada descripción, cantidad, precio e impuesto antes de enviar un documento, y de los acuerdos que hagas con tus clientes. Cotiza no da asesoría legal, fiscal ni contable.</p>

  <h2>Contacto</h2>
  <p><a href="mailto:{EMAIL}">{EMAIL}</a></p>
""")

(SITE / "404.html").write_text(f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Page not found — Cotiza</title>
<link rel="icon" href="/assets/icon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{CSS}">
</head>
<body>
<main class="wrap">
  <div class="hero">
    <img class="icon" src="/assets/icon.svg" alt="">
    <h1>Page not found</h1>
    <p class="lede">Página no encontrada.</p>
    <a class="cta" href="/">Cotiza</a>
  </div>
</main>
</body>
</html>
""")

print("Built", sorted(str(p.relative_to(SITE)) for p in SITE.rglob("*.html")))
