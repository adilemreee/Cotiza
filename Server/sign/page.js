// The page the client opens from the link: the estimate, a link to the PDF, and a signature pad.
// One self-contained HTML document; the only script is inline and allowed by a per-request nonce.

const STRINGS = {
  en: {
    lang: "en",
    title: (n) => `Estimate ${n}`,
    preparedFor: "Prepared for",
    from: "From",
    validUntil: "Valid until",
    item: "Item",
    amount: "Amount",
    total: "Total",
    notes: "Notes",
    terms: "Terms",
    viewPdf: "View the full PDF",
    signHeading: "Approve this estimate",
    name: "Your full name",
    signHere: "Sign here with your finger or mouse",
    clear: "Clear",
    agree: "I approve this work, the price and the terms of this estimate.",
    approve: "Approve and sign",
    sending: "Sending…",
    signedHeading: "Approved. Thank you!",
    signedBody: (name, date) => `Signed by ${name} on ${date}. You can close this page.`,
    expired: "This link has expired. Ask your contractor for a new one.",
    missing: "This link isn't valid anymore. Ask your contractor for a new one.",
    needName: "Please type your name.",
    needSignature: "Please sign in the box.",
    needAgree: "Please check the box to approve.",
    failed: "That didn't go through. Check your connection and try again.",
    footer: "Sent with Precia",
    preview: (total) => `Total ${total} · Review and sign online`,
  },
  es: {
    lang: "es",
    title: (n) => `Cotización ${n}`,
    preparedFor: "Preparada para",
    from: "De",
    validUntil: "Válida hasta",
    item: "Concepto",
    amount: "Importe",
    total: "Total",
    notes: "Notas",
    terms: "Términos",
    viewPdf: "Ver el PDF completo",
    signHeading: "Aprobar esta cotización",
    name: "Su nombre completo",
    signHere: "Firme aquí con el dedo o el ratón",
    clear: "Borrar",
    agree: "Apruebo este trabajo, el precio y los términos de esta cotización.",
    approve: "Aprobar y firmar",
    sending: "Enviando…",
    signedHeading: "Aprobada. ¡Gracias!",
    signedBody: (name, date) => `Firmada por ${name} el ${date}. Ya puede cerrar esta página.`,
    expired: "Este enlace ya venció. Pídale uno nuevo a su contratista.",
    missing: "Este enlace ya no es válido. Pídale uno nuevo a su contratista.",
    needName: "Escriba su nombre, por favor.",
    needSignature: "Firme en el recuadro, por favor.",
    needAgree: "Marque la casilla para aprobar, por favor.",
    failed: "No se pudo enviar. Revise su conexión e inténtelo de nuevo.",
    footer: "Enviada con Precia",
    preview: (total) => `Total ${total} · Revísela y fírmela en línea`,
  },
  tr: {
    lang: "tr",
    title: (n) => `Teklif ${n}`,
    preparedFor: "Hazırlanan",
    from: "Gönderen",
    validUntil: "Geçerlilik",
    item: "Kalem",
    amount: "Tutar",
    total: "Toplam",
    notes: "Notlar",
    terms: "Koşullar",
    viewPdf: "PDF'in tamamını görüntüle",
    signHeading: "Bu teklifi onaylayın",
    name: "Adınız soyadınız",
    signHere: "Parmağınızla ya da fareyle buraya imzalayın",
    clear: "Temizle",
    agree: "Bu işi, fiyatı ve teklifin koşullarını onaylıyorum.",
    approve: "Onayla ve imzala",
    sending: "Gönderiliyor…",
    signedHeading: "Onaylandı. Teşekkürler!",
    signedBody: (name, date) => `${name} tarafından ${date} tarihinde imzalandı. Bu sayfayı kapatabilirsiniz.`,
    expired: "Bu bağlantının süresi doldu. Ustanızdan yenisini isteyin.",
    missing: "Bu bağlantı artık geçerli değil. Ustanızdan yenisini isteyin.",
    needName: "Lütfen adınızı yazın.",
    needSignature: "Lütfen kutuya imzalayın.",
    needAgree: "Onaylamak için lütfen kutuyu işaretleyin.",
    failed: "Gönderilemedi. Bağlantınızı kontrol edip tekrar deneyin.",
    footer: "Precia ile gönderildi",
    preview: (total) => `Toplam ${total} · İnceleyin ve çevrimiçi imzalayın`,
  },
};

const LOCALES = { en: "en-US", es: "es-US", tr: "tr-TR" };

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

function formatDate(ms, language) {
  return new Date(ms).toLocaleDateString(LOCALES[language] ?? "en-US", { year: "numeric", month: "long", day: "numeric" });
}

const CSS = `
:root{--accent:#d9551a;--accent-dark:#b8430f;--ink:#17181d;--muted:#6b6f78;--line:#e6e2dc;--bg:#f6f3ef;--card:#fff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;-webkit-text-size-adjust:100%}
.top{background:var(--accent);color:#fff;padding:28px 20px 72px}
.top .wrap{max-width:640px;margin:0 auto}
.kind{font-size:13px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;opacity:.85}
h1{font-size:28px;line-height:1.15;margin:6px 0 4px;font-weight:800;letter-spacing:-.01em}
.from{opacity:.9;font-size:15px}
main{max-width:640px;margin:-48px auto 40px;padding:0 16px}
.card{background:var(--card);border-radius:20px;padding:20px;box-shadow:0 6px 24px rgba(60,30,10,.08);margin-bottom:16px}
.meta{display:flex;flex-wrap:wrap;gap:14px 28px;font-size:14px}
.meta div span{display:block;color:var(--muted);font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:.05em}
table{width:100%;border-collapse:collapse;margin-top:6px}
td{padding:11px 0;border-bottom:1px solid var(--line);vertical-align:top}
td.amt{text-align:right;white-space:nowrap;padding-left:12px;font-variant-numeric:tabular-nums}
.detail{color:var(--muted);font-size:13px}
.totals td{border:0;padding:4px 0;color:var(--muted)}
.grand td{padding-top:12px;font-size:20px;font-weight:800;color:var(--ink);border-top:2px solid var(--ink)}
.small{color:var(--muted);font-size:14px;white-space:pre-wrap}
h2{font-size:13px;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;margin:0 0 6px}
a.pdf{display:inline-block;margin-top:14px;color:var(--accent);font-weight:600;text-decoration:none}
label{display:block;font-weight:600;font-size:14px;margin:14px 0 6px}
input[type=text]{width:100%;font:inherit;font-size:17px;padding:12px 14px;border:1px solid var(--line);border-radius:12px;background:#fff}
.pad{position:relative;border:1px solid var(--line);border-radius:14px;background:#fff;touch-action:none;height:190px}
.pad canvas{position:absolute;inset:0;width:100%;height:100%;border-radius:14px}
.pad .hint{position:absolute;left:18px;bottom:16px;color:#a5a8ae;font-size:13px;pointer-events:none}
.pad .base{position:absolute;left:18px;right:18px;bottom:40px;border-top:1px solid #d7d9dd;pointer-events:none}
.row{display:flex;justify-content:flex-end;margin-top:6px}
button.link{background:none;border:0;color:var(--accent);font:inherit;font-size:14px;font-weight:600;padding:6px}
.agree{display:flex;gap:10px;align-items:flex-start;margin:16px 0;font-size:15px}
.agree input{width:22px;height:22px;accent-color:var(--accent);margin-top:1px;flex:none}
button.primary{width:100%;font:inherit;font-size:18px;font-weight:700;color:#fff;background:var(--accent);border:0;border-radius:16px;padding:16px;cursor:pointer}
button.primary:disabled{opacity:.6}
.error{color:#c0392b;font-size:14px;min-height:20px;margin-top:10px}
.done{text-align:center;padding:28px 20px}
.done .check{width:56px;height:56px;border-radius:50%;background:#1f9d55;color:#fff;font-size:30px;line-height:56px;margin:0 auto 12px}
.done h2{font-size:22px;color:var(--ink);text-transform:none;letter-spacing:0;margin:0 0 6px}
footer{text-align:center;color:var(--muted);font-size:12px;margin:24px 0}
`;

const SCRIPT = (s, id) => `
(() => {
  const S = ${JSON.stringify({ needName: s.needName, needSignature: s.needSignature, needAgree: s.needAgree, failed: s.failed, sending: s.sending, approve: s.approve })};
  const canvas = document.getElementById("pad");
  if (!canvas) return;
  const hint = document.getElementById("hint");
  const ctx = canvas.getContext("2d");
  let strokes = [], current = null;
  function size() {
    const r = canvas.getBoundingClientRect(), d = window.devicePixelRatio || 1;
    canvas.width = r.width * d; canvas.height = r.height * d;
    ctx.setTransform(d, 0, 0, d, 0, 0); draw();
  }
  function draw() {
    const r = canvas.getBoundingClientRect();
    ctx.clearRect(0, 0, r.width, r.height);
    ctx.lineWidth = 2.6; ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.strokeStyle = "#111";
    for (const st of strokes) {
      ctx.beginPath(); ctx.moveTo(st[0].x, st[0].y);
      if (st.length === 1) ctx.lineTo(st[0].x + .5, st[0].y + .5);
      for (const p of st) ctx.lineTo(p.x, p.y);
      ctx.stroke();
    }
    hint.style.opacity = strokes.length ? 0 : 1;
  }
  const point = (e) => { const r = canvas.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
  canvas.addEventListener("pointerdown", (e) => { canvas.setPointerCapture(e.pointerId); current = [point(e)]; strokes.push(current); draw(); });
  canvas.addEventListener("pointermove", (e) => { if (current) { current.push(point(e)); draw(); } });
  const end = () => { current = null; };
  canvas.addEventListener("pointerup", end); canvas.addEventListener("pointercancel", end);
  window.addEventListener("resize", () => { const old = strokes; size(); strokes = old; draw(); });
  document.getElementById("clear").addEventListener("click", () => { strokes = []; draw(); });
  size();

  // Black ink on transparent, cropped to the ink, at 3x: what the app prints on the PDF.
  function png() {
    const pts = strokes.flat();
    const xs = pts.map(p => p.x), ys = pts.map(p => p.y), pad = 6, k = 3;
    const x0 = Math.min(...xs) - pad, y0 = Math.min(...ys) - pad;
    const w = Math.max(...xs) - x0 + pad, h = Math.max(...ys) - y0 + pad;
    const out = document.createElement("canvas"); out.width = Math.ceil(w * k); out.height = Math.ceil(h * k);
    const c = out.getContext("2d"); c.scale(k, k); c.translate(-x0, -y0);
    c.lineWidth = 2.6; c.lineCap = "round"; c.lineJoin = "round"; c.strokeStyle = "#000";
    for (const st of strokes) {
      c.beginPath(); c.moveTo(st[0].x, st[0].y);
      if (st.length === 1) c.lineTo(st[0].x + .5, st[0].y + .5);
      for (const p of st) c.lineTo(p.x, p.y);
      c.stroke();
    }
    return out.toDataURL("image/png");
  }

  const form = document.getElementById("sign"), error = document.getElementById("error"), button = document.getElementById("approve");
  form.addEventListener("submit", async (e) => {
    e.preventDefault(); error.textContent = "";
    const name = document.getElementById("name").value.trim();
    if (!name) return (error.textContent = S.needName);
    if (strokes.flat().length < 2) return (error.textContent = S.needSignature);
    if (!document.getElementById("agree").checked) return (error.textContent = S.needAgree);
    button.disabled = true; button.textContent = S.sending;
    try {
      const res = await fetch(${JSON.stringify(`/s/${id}/sign`)}, { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, signature: png(), agree: true }) });
      if (res.ok || res.status === 409 || res.status === 410) { location.reload(); return; }
      throw new Error();
    } catch { error.textContent = S.failed; button.disabled = false; button.textContent = S.approve; }
  });
})();
`;

export function renderPage({ language, state, nonce, id, document: d, signerName, signedAt, publicURL = "" }) {
  const s = STRINGS[language] ?? STRINGS.en;
  // The card WhatsApp, iMessage and others show for the link: "Cotización E-1003 · López Painting LLC".
  const title = d ? [d.kindLabel && d.number ? `${d.kindLabel} ${d.number}` : s.title(d.number), d.businessName].filter(Boolean).join(" · ") : "Precia";
  const description = d ? [d.title, s.preview(d.total)].filter(Boolean).join(" — ") : "";
  const card = `${publicURL}/s/card-${s.lang}.png`;
  const preview = `<meta property="og:type" content="website"><meta property="og:site_name" content="Precia">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="${esc(card)}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta property="og:image:alt" content="${esc(title)}"><meta property="og:url" content="${esc(`${publicURL}/s/${id ?? ""}`)}">
<meta name="twitter:card" content="summary_large_image"><meta name="description" content="${esc(description)}">`;
  const head = `<!doctype html><html lang="${s.lang}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow"><meta name="theme-color" content="#d9551a">
<title>${esc(title)}</title>${d ? preview : ""}<style>${CSS}</style></head><body>`;

  if (!d || state === "missing" || state === "expired") {
    return `${head}<div class="top"><div class="wrap"><div class="kind">Precia</div></div></div>
<main><div class="card done"><p>${esc(state === "expired" ? s.expired : s.missing)}</p></div></main></body></html>`;
  }

  const items = d.items.map((i) => `<tr><td>${esc(i.text)}${i.detail ? `<div class="detail">${esc(i.detail)}</div>` : ""}</td><td class="amt">${esc(i.amount)}</td></tr>`).join("");
  const totals = d.totals.map((t) => `<tr class="totals"><td>${esc(t.label)}</td><td class="amt">${esc(t.value)}</td></tr>`).join("");
  const meta = [
    d.clientName && `<div><span>${s.preparedFor}</span>${esc(d.clientName)}</div>`,
    d.dateText && `<div><span>${esc(d.kindLabel || s.title(""))}</span>${esc(d.number)} · ${esc(d.dateText)}</div>`,
    d.validUntilText && `<div><span>${s.validUntil}</span>${esc(d.validUntilText)}</div>`,
  ].filter(Boolean).join("");

  const signed = state === "signed";
  const action = signed
    ? `<div class="card done"><div class="check">✓</div><h2>${s.signedHeading}</h2>
       <p class="small">${esc(s.signedBody(signerName, formatDate(signedAt, language)))}</p></div>`
    : `<form class="card" id="sign" novalidate><h2>${s.signHeading}</h2>
       <label for="name">${s.name}</label><input type="text" id="name" autocomplete="name" value="${esc(d.clientName)}">
       <label>${s.signHere}</label>
       <div class="pad"><div class="base"></div><span class="hint" id="hint">${s.signHere}</span><canvas id="pad" aria-label="${s.signHere}"></canvas></div>
       <div class="row"><button type="button" class="link" id="clear">${s.clear}</button></div>
       <label class="agree"><input type="checkbox" id="agree"><span>${s.agree}</span></label>
       <button class="primary" id="approve" type="submit">${s.approve}</button>
       <div class="error" id="error" role="alert"></div></form>`;

  return `${head}
<div class="top"><div class="wrap">
  <div class="kind">${esc(d.kindLabel)}</div>
  <h1>${esc(d.title || s.title(d.number))}</h1>
  <div class="from">${s.from} ${esc(d.businessName)}</div>
</div></div>
<main>
  <div class="card">
    <div class="meta">${meta}</div>
    <table>${items}${totals}<tr class="grand"><td>${s.total}</td><td class="amt">${esc(d.total)}</td></tr></table>
    <a class="pdf" href="/s/${esc(id)}/document.pdf" target="_blank" rel="noopener">${s.viewPdf} ›</a>
  </div>
  ${d.notes ? `<div class="card"><h2>${s.notes}</h2><div class="small">${esc(d.notes)}</div></div>` : ""}
  ${d.terms ? `<div class="card"><h2>${s.terms}</h2><div class="small">${esc(d.terms)}</div></div>` : ""}
  ${action}
  ${d.businessContact ? `<p class="small" style="text-align:center">${esc(d.businessName)} · ${esc(d.businessContact)}</p>` : ""}
  <footer>${s.footer}</footer>
</main>
${signed ? "" : `<script nonce="${esc(nonce)}">${SCRIPT(s, id)}</script>`}
</body></html>`;
}
