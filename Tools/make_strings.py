"""Builds the String Catalogs (English source, Spanish translation).

Run after a build:  python3 Tools/make_strings.py
It reads the keys the compiler extracted and fails if any is missing a Spanish translation.
"""
import glob
import json
import sys

NO_TRANSLATE = {"%@", "%@ · %@", "iCloud", "%@ × %@", "WhatsApp", "0", "1", "·", "EN", "ES", "Cotiza", "Cotiza %@", "Cotiza Pro", "Zelle", "Cash App", "Venmo"}

ES = {
    "Amount ($)": "Monto ($)",
    "Ask for a deposit, record each payment and always know what's still owed.": "Pide un anticipo, registra cada pago y sabe siempre cuánto te deben.",
    "Balance before this payment: %@": "Saldo antes de este pago: %@",
    "Balance due": "Saldo pendiente",
    "Card": "Tarjeta",
    "Cash": "Efectivo",
    "Check": "Cheque",
    "Date": "Fecha",
    "Deposit": "Anticipo",
    "Deposit to start (%)": "Anticipo para empezar (%)",
    "Deposit: %@": "Anticipo: %@",
    "Deposits and partial payments": "Anticipos y pagos parciales",
    "Each payment counts in your report on the day you got it. Paid in full, the document is marked paid.": "Cada pago cuenta en tu reporte el día en que lo recibiste. Al pagarse completo, el documento queda como pagado.",
    "Everything: %@": "Todo: %@",
    "Income is counted on the day you get paid, deposits and partial payments included. Materials cost comes from scanned receipts and the cost you enter on each item.": "Los ingresos cuentan el día en que te pagan, incluidos anticipos y pagos parciales. El costo de materiales sale de los recibos escaneados y del costo que escribes en cada concepto.",
    "Owes %@": "Debe %@",
    "Paid with": "Pagado con",
    "Payments": "Pagos",
    "Printed on invoices, and on estimates that ask for a deposit. New estimates ask for this deposit; 0 means none.": "Aparece en las facturas y en las cotizaciones que piden anticipo. Las cotizaciones nuevas piden este anticipo; 0 es sin anticipo.",
    "Record a payment": "Registrar un pago",
    "Save": "Guardar",
    "The deposit is printed on the estimate. Record it when the client pays; it moves to the invoice.": "El anticipo aparece en la cotización. Regístralo cuando el cliente pague; pasa a la factura.",
    "Cotiza uses this to understand the jobs you describe.": "Cotiza lo usa para entender los trabajos que describes.",
    "Other": "Otro",
    "What do you do? For example: pool cleaning": "¿A qué te dedicas? Por ejemplo: limpieza de albercas",
    "Rate Cotiza on the App Store": "Califica Cotiza en el App Store",
    "%@ approved %@": "%@ aprobó %@",
    "Cancel the link": "Cancelar el enlace",
    "Check now": "Revisar ahora",
    "Hand the phone to your client, or send a link they can sign from anywhere. Signing approves the estimate and the signature is printed on the PDF.": "Pásale el teléfono a tu cliente o envíale un enlace para firmar desde donde esté. Al firmar, aprueba la cotización y la firma aparece en el PDF.",
    "Link sent %@": "Enlace enviado %@",
    "Send a signing link": "Enviar enlace para firmar",
    "Share the link again": "Compartir el enlace otra vez",
    "The estimate was signed online. The signature is on the PDF.": "La cotización se firmó en línea. La firma ya está en el PDF.",
    "The signing link couldn't be created. Check your connection and try again.": "No se pudo crear el enlace para firmar. Revisa tu conexión e inténtalo de nuevo.",
    "Waiting for the client to sign": "Esperando la firma del cliente",
    "When your client signs, the estimate is approved and you get a notification.": "Cuando tu cliente firme, la cotización queda aprobada y recibes una notificación.",
    "%@ per week": "%@ a la semana",
    "Weekly": "Semanal",
    "Profit reports": "Reportes de ganancias",
    "Income, materials and profit by month, ready for your accountant.": "Ingresos, materiales y ganancia por mes, listos para tu contador.",
    "%@: a new copy of %@ is ready to send.": "%@: hay una copia nueva de %@ lista para enviar.",
    "Cost %@": "Costo %@",
    "Every 2 weeks": "Cada 2 semanas",
    "Every month": "Cada mes",
    "Every week": "Cada semana",
    "Export": "Exportar",
    "Income is counted on the day a job is marked paid. Materials cost comes from scanned receipts and the cost you enter on each item.": "Los ingresos cuentan el día en que marcas el trabajo como pagado. El costo de materiales sale de los recibos escaneados y del costo que escribes en cada concepto.",
    "Invoice ready to send": "Factura lista para enviar",
    "Jobs paid: %lld": "Trabajos pagados: %lld",
    "Markup on materials": "Ganancia sobre materiales",
    "Markup on materials (%)": "Ganancia sobre materiales (%)",
    "Materials cost": "Costo de materiales",
    "Month": "Mes",
    "Never": "Nunca",
    "Next": "Siguiente",
    "Next invoice": "Próxima factura",
    "No jobs were paid in this period.": "No hay trabajos pagados en este periodo.",
    "On that day Cotiza makes a copy of this invoice with a new number and reminds you to send it.": "Ese día Cotiza hace una copia de esta factura con un número nuevo y te recuerda enviarla.",
    "PDF summary": "Resumen en PDF",
    "Period": "Periodo",
    "Previous": "Anterior",
    "Profit": "Ganancia",
    "Profit %@": "Ganancia %@",
    "Repeat": "Repetir",
    "Reports": "Reportes",
    "Revenue (before tax)": "Ingresos (sin impuesto)",
    "Sales tax collected": "Impuesto cobrado",
    "Sign in to iCloud in the Settings app to back up and sync": "Inicia sesión en iCloud en la app Ajustes para respaldar y sincronizar",
    "Spreadsheet (CSV)": "Hoja de cálculo (CSV)",
    "Synced with iCloud": "Sincronizado con iCloud",
    "Year": "Año",
    "Your cost is only for your profit report. The client never sees it.": "Tu costo es solo para tu reporte de ganancias. El cliente nunca lo ve.",
    "Your cost is saved for your profit report. The client only sees the price with markup.": "Tu costo se guarda para tu reporte de ganancias. El cliente solo ve el precio con tu ganancia.",
    "Your cost per unit ($)": "Tu costo por unidad ($)",
    "Your jobs, clients and prices are kept in your private iCloud and appear on every iPhone and iPad signed in to your Apple Account. We can't see them.": "Tus trabajos, clientes y precios se guardan en tu iCloud privado y aparecen en cada iPhone y iPad con tu cuenta de Apple. Nosotros no podemos verlos.",
    "iCloud sync isn't available right now": "La sincronización con iCloud no está disponible ahora",
    "Client signs on your phone": "Tu cliente firma en tu teléfono",
    "Approved on the spot, with the signature on the PDF.": "Aprobada ahí mismo, con la firma en el PDF.",
    "%@ has been waiting %lld days for an answer (%@).": "%@ lleva %lld días esperando respuesta (%@).",
    "%@ is overdue": "%@ está vencida",
    "%@ was due %@.": "%@ venció el %@.",
    "%lld days": "%lld días",
    "Add %lld items · %@": "Agregar %lld conceptos · %@",
    "Add materials from a receipt": "Agrega materiales desde un recibo",
    "Awaiting %@": "Por cobrar %@",
    "Awaiting payment": "Por cobrar",
    "Choose a photo": "Elegir una foto",
    "Choose from Contacts": "Elegir de Contactos",
    "Client approval": "Aprobación del cliente",
    "Client signature": "Firma del cliente",
    "Cotiza reads the items and prices on your phone. You choose which ones to add.": "Cotiza lee los artículos y precios en tu teléfono. Tú eliges cuáles agregar.",
    "Cotiza reminds you when an estimate has waited %lld days for an answer and when an invoice is past due.": "Cotiza te avisa cuando una cotización lleva %lld días sin respuesta y cuando una factura está vencida.",
    "Dates and reminders": "Fechas y recordatorios",
    "Email or other apps": "Correo u otras apps",
    "Estimates valid for": "Cotizaciones válidas por",
    "Fill in from Contacts": "Llenar desde Contactos",
    "Follow up on your estimate": "Dale seguimiento a tu cotización",
    "Found on the receipt": "Encontrado en el recibo",
    "Get client signature": "Pedir firma del cliente",
    "Money owed": "Lo que me deben",
    "No prices found": "No se encontraron precios",
    "Not selected": "No seleccionado",
    "Overdue": "Vencida",
    "Overdue: %lld": "Vencidas: %lld",
    "Paid this month: %@": "Cobrado este mes: %@",
    "Payment due": "Fecha de pago",
    "Payment due after": "Plazo de pago",
    "Printed on the PDF.": "Aparece en el PDF.",
    "Reading the receipt…": "Leyendo el recibo…",
    "Reminders": "Recordatorios",
    "Remove signature": "Quitar firma",
    "Scan a receipt": "Escanear un recibo",
    "Selected": "Seleccionado",
    "Signed by %@": "Firmado por %@",
    "Start describing a job from the Lock Screen.": "Describe un trabajo desde la pantalla bloqueada.",
    "Take a photo": "Tomar una foto",
    "Text message": "Mensaje de texto",
    "Totals, tax and payment lines are left out. Check each price before sending.": "Se omiten totales, impuestos y pagos. Revisa cada precio antes de enviar.",
    "Try again with the whole receipt flat, in good light.": "Inténtalo otra vez con el recibo completo, plano y con buena luz.",
    "Valid until": "Válida hasta",
    "What your clients still owe you and what came in this month.": "Lo que tus clientes aún te deben y lo que cobraste este mes.",
    "%@ is paid: %@.": "%@ quedó pagada: %@.",
    "Awaiting payment: %@. Paid this month: %@.": "Por cobrar: %@. Cobrado este mes: %@.",
    "Document": "Documento",
    "Estimate or invoice": "Cotización o factura",
    "Mark ${document} as paid": "Marcar ${document} como pagada",
    "Marks an estimate or invoice as paid.": "Marca una cotización o factura como pagada.",
    "Money owed to me": "Lo que me deben",
    "Open document": "Abrir documento",
    "Opens an estimate or invoice in Cotiza.": "Abre una cotización o factura en Cotiza.",
    "Says how much your clients still owe you and how much you were paid this month.": "Te dice cuánto te deben tus clientes y cuánto cobraste este mes.",
    "That document is no longer in Cotiza.": "Ese documento ya no está en Cotiza.",
    "Which estimate or invoice?": "¿Qué cotización o factura?",
    "Which one was paid?": "¿Cuál te pagaron?",
    "%@ per month": "%@ al mes",
    "%@ per year": "%@ al año",
    "%@. Renews automatically. Cancel anytime in the App Store.": "%@. Se renueva automáticamente. Cancela cuando quieras en el App Store.",
    "Documents: %lld": "Documentos: %lld",
    "Items without a price: %lld": "Conceptos sin precio: %lld",
    "Active": "Activa",
    "Add client": "Agregar cliente",
    "Add from my prices": "Agregar de mis precios",
    "Add item": "Agregar concepto",
    "Add price": "Poner precio",
    "Address": "Dirección",
    "All": "Todo",
    "Approved": "Aprobada",
    "Awaiting reply": "En espera",
    "Back": "Atrás",
    "Business name": "Nombre del negocio",
    "Cancel": "Cancelar",
    "Change logo": "Cambiar logo",
    "Choose logo": "Elegir logo",
    "Cleaning": "Limpieza",
    "Client": "Cliente",
    "Clients": "Clientes",
    "Clients are saved when you add them to an estimate.": "Los clientes se guardan cuando los agregas a una cotización.",
    "Close": "Cerrar",
    "Concrete": "Concreto",
    "Contact support": "Contactar a soporte",
    "Continue": "Continuar",
    "Convert to invoice": "Convertir en factura",
    "Cotiza remembers your prices each time you send an estimate.": "Cotiza recuerda tus precios cada vez que envías una cotización.",
    "Couldn't create the PDF": "No se pudo crear el PDF",
    "Create estimate": "Crear cotización",
    "Defaults for new estimates": "Valores para cotizaciones nuevas",
    "Delete": "Eliminar",
    "Delete item": "Eliminar concepto",
    "Delete this document?": "¿Eliminar este documento?",
    "Describe the job and your prices.": "Describe el trabajo y tus precios.",
    "Describe the work in Spanish or English. Cotiza writes a professional estimate your client can approve on the spot.": "Describe el trabajo en español o en inglés. Cotiza escribe una cotización profesional que tu cliente puede aprobar ahí mismo.",
    "Description": "Descripción",
    "Document language": "Idioma del documento",
    "Didn't catch that. Tap to try again, or type the job.": "No te escuché. Toca para intentarlo de nuevo o escribe el trabajo.",
    "Done": "Listo",
    "Draft": "Borrador",
    "Drywall": "Tablaroca",
    "Duplicate": "Duplicar",
    "Edit": "Editar",
    "Electrical": "Electricidad",
    "Email": "Correo electrónico",
    "English": "Inglés",
    "Estimate": "Cotización",
    "Estimates": "Cotizaciones",
    "Example:": "Ejemplo:",
    "Example: 50% deposit to start, balance on completion.": "Ejemplo: 50% de anticipo para empezar y el resto al terminar.",
    "Example: Zelle 555-123-4567, check or cash.": "Ejemplo: Zelle 555-123-4567, cheque o efectivo.",
    "Flooring": "Pisos",
    "Free plan: %lld of %lld estimates left": "Plan gratis: te quedan %lld de %lld cotizaciones",
    "Free trial, then %@. Renews automatically. Cancel anytime in the App Store.": "Prueba gratis, después %@. Se renueva automáticamente. Cancela cuando quieras en el App Store.",
    "Free up some storage and try again.": "Libera espacio en tu teléfono e inténtalo de nuevo.",
    "General contractor": "Contratista general",
    "Get started": "Empezar",
    "Go Pro": "Hazte Pro",
    "Handyman": "Mantenimiento",
    "Heating & air": "Aire y calefacción",
    "Help and FAQ": "Ayuda y preguntas frecuentes",
    "How clients pay you": "Cómo te pagan tus clientes",
    "I speak": "Yo hablo",
    "Invoice": "Factura",
    "Invoices": "Facturas",
    "Invoices in one tap": "Facturas con un toque",
    "Item": "Concepto",
    "Items": "Conceptos",
    "Job address": "Dirección del trabajo",
    "Job title": "Nombre del trabajo",
    "Labor": "Mano de obra",
    "Landscaping": "Jardinería",
    "License number": "Número de licencia",
    "Line total": "Total del concepto",
    "Listening… tap to stop": "Escuchando… toca para parar",
    "Logo": "Logo",
    "Look professional. Win more jobs. Get paid faster.": "Luce profesional. Gana más trabajos. Cobra más rápido.",
    "Manage subscription": "Administrar suscripción",
    "Mark as paid": "Marcar como pagada",
    "Microphone access is off. You can still type the job.": "El micrófono está desactivado. Puedes escribir el trabajo.",
    "Monthly": "Mensual",
    "More": "Más",
    "My prices": "Mis precios",
    "Name": "Nombre",
    "New client": "Cliente nuevo",
    "New estimate": "Nueva cotización",
    "New item": "Concepto nuevo",
    "No Cotiza footer on what your client sees.": "Sin la marca de Cotiza en lo que ve tu cliente.",
    "No active subscription was found for this Apple Account.": "No se encontró una suscripción activa en esta cuenta de Apple.",
    "No clients yet": "Aún no hay clientes",
    "No saved prices": "Aún no hay precios guardados",
    "Notes for the client": "Notas para el cliente",
    "Nothing here yet.": "Aún no hay nada aquí.",
    "OK": "OK",
    "Only %@ per month": "Solo %@ al mes",
    "Open Cotiza ready to describe a job by voice.": "Abre Cotiza listo para describir un trabajo con tu voz.",
    "Open Settings": "Abrir Ajustes",
    "Paid": "Pagada",
    "Paid this month": "Cobrado del mes",
    "Painting": "Pintura",
    "Phone": "Teléfono",
    "Plans couldn't be loaded. Check your connection and try again.": "No se pudieron cargar los planes. Revisa tu conexión e inténtalo de nuevo.",
    "Plumbing": "Plomería",
    "Preview and send": "Ver y enviar",
    "Price": "Precio",
    "Price per unit ($)": "Precio por unidad ($)",
    "Prices, quantities and tasks become line items automatically.": "Los precios, cantidades y trabajos se convierten en conceptos automáticamente.",
    "Printed at the bottom of every document.": "Aparecen al final de cada documento.",
    "Printed on invoices.": "Aparece en las facturas.",
    "Privacy": "Privacidad",
    "Privacy policy": "Política de privacidad",
    "Private by design": "Privado por diseño",
    "Quantity": "Cantidad",
    "Quote every job, every day.": "Cotiza todos los trabajos, todos los días.",
    "Remembers your prices": "Recuerda tus precios",
    "Remove": "Quitar",
    "Remove client from this document": "Quitar al cliente de este documento",
    "Restore purchases": "Restaurar compras",
    "Roofing": "Techos",
    "Sales tax (%)": "Impuesto (%)",
    "Save %lld%%": "Ahorra %lld%%",
    "Say the job. Send the estimate.": "Di el trabajo. Envía la cotización.",
    "Search or type a new name": "Busca o escribe un nombre nuevo",
    "Send to client": "Enviar al cliente",
    "Sent": "Enviada",
    "Set up": "Configuración",
    "Settings": "Ajustes",
    "Show": "Mostrar",
    "Something went wrong": "Algo salió mal",
    "Spanish": "Español",
    "Speak Spanish, send English": "Habla español, envía en inglés",
    "Speak in any language. The estimate is written in the document language.": "Habla en cualquier idioma. La cotización se escribe en el idioma del documento.",
    "Start recording": "Empezar a grabar",
    "Start with a blank estimate": "Empezar con una cotización en blanco",
    "Status": "Estado",
    "Stop recording": "Parar la grabación",
    "Subscribe": "Suscribirme",
    "Subtotal": "Subtotal",
    "Talk, don't type": "Habla, no escribas",
    "Tap the button below and describe the job out loud, with your prices.": "Toca el botón de abajo y describe el trabajo en voz alta, con tus precios.",
    "Tap to add more": "Toca para agregar más",
    "Tap to speak": "Toca para hablar",
    "Tax": "Impuesto",
    "Tax applies only to items marked taxable.": "El impuesto solo se aplica a los conceptos marcados como gravables.",
    "Taxable": "Gravable",
    "Terms": "Términos",
    "Terms of use": "Términos de uso",
    "This appears at the top of every estimate. You can change it later.": "Aparece arriba en cada cotización. Puedes cambiarlo después.",
    "This can't be undone.": "Esto no se puede deshacer.",
    "Timeline, deposit, what's included…": "Fechas, anticipo, qué incluye…",
    "Total": "Total",
    "Trade": "Oficio",
    "Try %lld days free": "Prueba %lld días gratis",
    "Try again": "Intentar de nuevo",
    "Turn an approved estimate into an invoice and track who paid.": "Convierte una cotización aprobada en factura y lleva el control de quién pagó.",
    "Unit": "Unidad",
    "Unlimited estimates": "Cotizaciones ilimitadas",
    "Unlimited estimates, invoices and your logo.": "Cotizaciones ilimitadas, facturas y tu logo.",
    "Unnamed client": "Cliente sin nombre",
    "Untitled job": "Trabajo sin nombre",
    "Upgrade to Cotiza Pro": "Pásate a Cotiza Pro",
    "Voice isn't available right now. Type the job instead.": "La voz no está disponible ahora. Escribe el trabajo.",
    "What is being done or supplied": "Qué se va a hacer o entregar",
    "What kind of work do you do?": "¿Qué tipo de trabajo haces?",
    "Writing your estimate…": "Escribiendo tu cotización…",
    "Yearly": "Anual",
    "Your business": "Tu negocio",
    "Your client gets a clean estimate in the language they read.": "Tu cliente recibe una cotización clara en el idioma que lee.",
    "Your first estimate takes one minute": "Tu primera cotización toma un minuto",
    "No account, no ads. Your jobs and prices stay with you.": "Sin cuenta ni anuncios. Tus trabajos y precios son solo tuyos.",
    "Your logo on estimates and invoices is part of Cotiza Pro.": "Tu logo en cotizaciones y facturas es parte de Cotiza Pro.",
    "Your logo, your brand": "Tu logo, tu marca",
    "Your name": "Tu nombre",
    "Your usual prices fill in by themselves.": "Tus precios de siempre se llenan solos.",
    "each": "c/u",
}

# The two example prompts are already written per language in code.
PASSTHROUGH_PREFIXES = ("“",)

SHORTCUTS_ES = {
    "New estimate in ${applicationName}": "Nueva cotización en ${applicationName}",
    "Start an estimate with ${applicationName}": "Empieza una cotización con ${applicationName}",
    "How much am I owed in ${applicationName}": "Cuánto me deben en ${applicationName}",
    "What do my clients owe me in ${applicationName}": "Qué me deben mis clientes en ${applicationName}",
    "Check my payments in ${applicationName}": "Revisa mis pagos en ${applicationName}",
    "Mark ${document} as paid in ${applicationName}": "Marca ${document} como pagada en ${applicationName}",
    "Mark a job as paid in ${applicationName}": "Marca un trabajo como pagado en ${applicationName}",
    "Open ${target} in ${applicationName}": "Abre ${target} en ${applicationName}",
    "Find a job in ${applicationName}": "Busca un trabajo en ${applicationName}",
}

INFO_PLIST_ES = {
    "NSMicrophoneUsageDescription": (
        "Cotiza uses the microphone so you can describe a job out loud and turn it into an estimate.",
        "Cotiza usa el micrófono para que describas un trabajo en voz alta y lo convierta en cotización.",
    ),
    "NSSpeechRecognitionUsageDescription": (
        "Cotiza transcribes what you say to build your estimate. Transcription happens on your device when possible.",
        "Cotiza transcribe lo que dices para armar tu cotización. La transcripción se hace en tu teléfono cuando es posible.",
    ),
    "NSCameraUsageDescription": (
        "Cotiza uses the camera to scan material receipts into your invoices.",
        "Cotiza usa la cámara para escanear recibos de materiales y agregarlos a tus facturas.",
    ),
    "NSPhotoLibraryUsageDescription": (
        "Cotiza lets you pick a logo for your estimates and invoices.",
        "Cotiza te deja elegir un logo para tus cotizaciones y facturas.",
    ),
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def extracted_keys(widget=False):
    """Keys of the app (widget=False) or of the widget extension (widget=True)."""
    keys = {}
    pattern = "build/DerivedData/Build/Intermediates.noindex/Cotiza.build/**/*.stringsdata"
    for path in glob.glob(pattern, recursive=True):
        if "CotizaTests" in path or ("CotizaWidget.build" in path) != widget:
            continue
        for table, entries in json.load(open(path)).get("tables", {}).items():
            keys.setdefault(table, set()).update(entry["key"] for entry in entries)
    return keys


def catalog(keys):
    strings, missing = {}, []
    for key in sorted(keys):
        if key in NO_TRANSLATE or key.startswith(PASSTHROUGH_PREFIXES):
            strings[key] = {"shouldTranslate": False}
        elif key in ES:
            strings[key] = {"localizations": {"es": unit(ES[key])}}
        else:
            missing.append(key)
    return strings, missing


def main():
    keys = extracted_keys()
    localizable = keys.get("Localizable") or set(ES) | NO_TRANSLATE
    widget_keys = extracted_keys(widget=True).get("Localizable", set())
    strings, missing = catalog(localizable)
    widget_strings, widget_missing = catalog(widget_keys)
    missing = sorted(set(missing) | set(widget_missing))
    unused = sorted(set(ES) - localizable - widget_keys)
    if missing:
        print("MISSING Spanish for:", *missing, sep="\n  ")
        sys.exit(1)
    if unused:
        print("Unused translations (safe to delete):", *unused, sep="\n  ")

    def write(path, body):
        catalog = {"sourceLanguage": "en", "strings": body, "version": "1.0"}
        with open(path, "w") as handle:
            json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")

    write("Cotiza/Resources/Localizable.xcstrings", strings)
    if widget_strings:
        write("CotizaWidget/Localizable.xcstrings", widget_strings)
    write("Cotiza/Resources/AppShortcuts.xcstrings",
          {key: {"localizations": {"es": unit(value)}} for key, value in SHORTCUTS_ES.items()})
    write("Cotiza/Resources/InfoPlist.xcstrings",
          {key: {"localizations": {"en": unit(en), "es": unit(es)}} for key, (en, es) in INFO_PLIST_ES.items()})
    print(f"Wrote {len(strings)} strings, all translated.")


main()
