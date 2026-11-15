// Cotiza signing links: the app uploads an estimate, the client opens a link and signs in the browser,
// the app fetches the signature and deletes the request.
//
// No dependencies: Node's own http and sqlite modules. Data lives in DATA_DIR (an SQLite file and PDFs).
// Nothing here is kept longer than it has to be: a request is deleted when the app collects the
// signature, and in any case 30 days after it was created or signed.
//
//   PORT=4130 DATA_DIR=./data PUBLIC_URL=https://cotiza.adilemree.xyz node server.js

import { createServer } from "node:http";
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { renderPage } from "./page.js";

const PORT = Number(process.env.PORT ?? 4130);
const DATA_DIR = process.env.DATA_DIR ?? "./data";
const PUBLIC_URL = (process.env.PUBLIC_URL ?? "https://cotiza.adilemree.xyz").replace(/\/$/, "");
const DAY = 24 * 60 * 60 * 1000;
const LIFETIME = 30 * DAY;
const MAX_BODY = 6 * 1024 * 1024; // the estimate PDF, base64
const MAX_PDF = 4 * 1024 * 1024;
const MAX_SIGNATURE = 600 * 1024;

mkdirSync(join(DATA_DIR, "pdf"), { recursive: true });
const db = new DatabaseSync(join(DATA_DIR, "sign.sqlite"));
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS requests (
    id TEXT PRIMARY KEY,
    secret_hash TEXT NOT NULL,
    language TEXT NOT NULL,
    document TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    signer_name TEXT,
    signature BLOB,
    signed_at INTEGER,
    signer_ip TEXT,
    signer_agent TEXT
  );
`);

// MARK: Helpers

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const newID = () => randomBytes(16).toString("base64url");

function secretMatches(row, secret) {
  if (!row || typeof secret !== "string" || secret.length < 32 || secret.length > 128) return false;
  const a = Buffer.from(row.secret_hash, "hex");
  const b = Buffer.from(sha256(secret), "hex");
  return a.length === b.length && timingSafeEqual(a, b);
}

function text(value, max) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function cleanDocument(input) {
  const d = input && typeof input === "object" ? input : {};
  const lines = (list) => (Array.isArray(list) ? list.slice(0, 200) : []);
  return {
    businessName: text(d.businessName, 120),
    businessContact: text(d.businessContact, 300),
    kindLabel: text(d.kindLabel, 40),
    number: text(d.number, 40),
    title: text(d.title, 200),
    clientName: text(d.clientName, 120),
    dateText: text(d.dateText, 60),
    validUntilText: text(d.validUntilText, 60),
    items: lines(d.items).map((i) => ({ text: text(i?.text, 400), detail: text(i?.detail, 80), amount: text(i?.amount, 40) })),
    totals: lines(d.totals).slice(0, 6).map((t) => ({ label: text(t?.label, 60), value: text(t?.value, 40) })),
    total: text(d.total, 40),
    notes: text(d.notes, 2000),
    terms: text(d.terms, 2000),
  };
}

const pdfPath = (id) => join(DATA_DIR, "pdf", `${id}.pdf`);

function remove(id) {
  db.prepare("DELETE FROM requests WHERE id = ?").run(id);
  rmSync(pdfPath(id), { force: true });
}

function purge(now = Date.now()) {
  const old = db
    .prepare("SELECT id FROM requests WHERE expires_at < ? OR (signed_at IS NOT NULL AND signed_at < ?)")
    .all(now, now - LIFETIME);
  for (const { id } of old) remove(id);
  return old.length;
}

// Small per-key limits, kept in memory: enough to stop a script from filling the disk or guessing.
const buckets = new Map();
function allowed(key, perHour) {
  const now = Date.now();
  const bucket = buckets.get(key) ?? { count: 0, start: now };
  if (now - bucket.start > 3600_000) { bucket.count = 0; bucket.start = now; }
  bucket.count += 1;
  buckets.set(key, bucket);
  return bucket.count <= perHour;
}
setInterval(() => {
  const cutoff = Date.now() - 3600_000;
  for (const [key, b] of buckets) if (b.start < cutoff) buckets.delete(key);
}, 600_000).unref();

function clientIP(req) {
  return String(req.headers["cf-connecting-ip"] ?? req.headers["x-forwarded-for"] ?? req.socket.remoteAddress ?? "")
    .split(",")[0].trim().slice(0, 64);
}

function send(res, status, body, headers = {}) {
  const isJSON = typeof body === "object" && !Buffer.isBuffer(body);
  const data = isJSON ? JSON.stringify(body) : body ?? "";
  res.writeHead(status, {
    "Content-Type": isJSON ? "application/json; charset=utf-8" : "text/plain; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow",
    ...headers,
  });
  res.end(data);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) { reject(Object.assign(new Error("too large"), { status: 413 })); req.destroy(); return; }
      chunks.push(chunk);
    });
    req.on("end", () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}")); }
      catch { reject(Object.assign(new Error("bad json"), { status: 400 })); }
    });
    req.on("error", reject);
  });
}

const LANGUAGES = ["en", "es", "tr"];
const CARDS = Object.fromEntries(LANGUAGES.map((l) => [l, readFileSync(new URL(`./card-${l}.png`, import.meta.url))]));

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const PDF = Buffer.from("%PDF-");

// MARK: Routes

async function handle(req, res) {
  const url = new URL(req.url, "http://local");
  const path = url.pathname;
  const ip = clientIP(req);
  if (!allowed(`all:${ip}`, 1200)) return send(res, 429, { error: "slow down" });

  if (path === "/api/v1/health") return send(res, 200, { ok: true });

  // The app creates a request.
  if (path === "/api/v1/sign-requests" && req.method === "POST") {
    if (!allowed(`create:${ip}`, 60)) return send(res, 429, { error: "slow down" });
    const body = await readBody(req);
    const secret = req.headers["x-cotiza-secret"];
    if (typeof secret !== "string" || secret.length < 32 || secret.length > 128) return send(res, 400, { error: "secret" });
    const pdf = Buffer.from(String(body.pdf ?? ""), "base64");
    if (pdf.length === 0 || pdf.length > MAX_PDF || !pdf.subarray(0, 5).equals(PDF)) return send(res, 400, { error: "pdf" });
    const language = LANGUAGES.includes(body.language) ? body.language : "en";
    const document = cleanDocument(body.document);
    if (!document.number || !document.total) return send(res, 400, { error: "document" });
    const id = newID();
    const now = Date.now();
    writeFileSync(pdfPath(id), pdf);
    db.prepare("INSERT INTO requests (id, secret_hash, language, document, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)")
      .run(id, sha256(secret), language, JSON.stringify(document), now, now + LIFETIME);
    return send(res, 201, { id, url: `${PUBLIC_URL}/s/${id}`, expiresAt: new Date(now + LIFETIME).toISOString() });
  }

  // The app checks on, or withdraws, a request.
  const api = path.match(/^\/api\/v1\/sign-requests\/([A-Za-z0-9_-]{22})$/);
  if (api) {
    const row = db.prepare("SELECT * FROM requests WHERE id = ?").get(api[1]);
    if (!secretMatches(row, req.headers["x-cotiza-secret"])) return send(res, 404, { error: "not found" });
    if (req.method === "DELETE") { remove(row.id); return send(res, 204, ""); }
    if (req.method === "GET") {
      return send(res, 200, {
        status: row.expires_at < Date.now() && row.status === "pending" ? "expired" : row.status,
        signerName: row.signer_name ?? null,
        signedAt: row.signed_at ? new Date(row.signed_at).toISOString() : null,
        signature: row.signature ? Buffer.from(row.signature).toString("base64") : null,
      });
    }
    return send(res, 405, { error: "method" });
  }

  // The link-preview card (Tools/make_link_card.py).
  const card = path.match(/^\/s\/card-(en|es|tr)\.png$/);
  if (card && req.method === "GET") {
    return send(res, 200, CARDS[card[1]], { "Content-Type": "image/png", "Cache-Control": "public, max-age=604800" });
  }

  // The client's page, the PDF and the signature.
  const page = path.match(/^\/s\/([A-Za-z0-9_-]{22})(\/document\.pdf|\/sign)?$/);
  if (page) {
    const row = db.prepare("SELECT * FROM requests WHERE id = ?").get(page[1]);
    const live = row && row.expires_at >= Date.now();
    if (page[2] === "/document.pdf" && req.method === "GET") {
      if (!live || !existsSync(pdfPath(row.id))) return send(res, 404, "Not found");
      const doc = JSON.parse(row.document);
      return send(res, 200, readFileSync(pdfPath(row.id)), {
        "Content-Type": "application/pdf",
        "Content-Disposition": `inline; filename="${(doc.number || "estimate").replace(/[^A-Za-z0-9-]/g, "")}.pdf"`,
      });
    }
    if (page[2] === "/sign" && req.method === "POST") {
      if (!allowed(`sign:${ip}`, 30)) return send(res, 429, { error: "slow down" });
      if (!live) return send(res, 410, { error: "expired" });
      if (row.status !== "pending") return send(res, 409, { error: "already signed" });
      const body = await readBody(req);
      const name = text(body.name, 120);
      const match = /^data:image\/png;base64,([A-Za-z0-9+/=]+)$/.exec(String(body.signature ?? ""));
      const png = match ? Buffer.from(match[1], "base64") : Buffer.alloc(0);
      if (!name || body.agree !== true) return send(res, 400, { error: "name" });
      if (png.length < 100 || png.length > MAX_SIGNATURE || !png.subarray(0, 8).equals(PNG)) return send(res, 400, { error: "signature" });
      const now = Date.now();
      db.prepare(`UPDATE requests SET status = 'signed', signer_name = ?, signature = ?, signed_at = ?, signer_ip = ?,
                  signer_agent = ?, expires_at = ? WHERE id = ? AND status = 'pending'`)
        .run(name, png, now, ip, String(req.headers["user-agent"] ?? "").slice(0, 300), now + LIFETIME, row.id);
      return send(res, 200, { ok: true, signedAt: new Date(now).toISOString() });
    }
    if (!page[2] && req.method === "GET") {
      const nonce = randomBytes(12).toString("base64");
      const wanted = String(req.headers["accept-language"] ?? "").slice(0, 2);
      const language = row?.language ?? (LANGUAGES.includes(wanted) ? wanted : "en");
      const state = !row ? "missing" : !live ? "expired" : row.status;
      const html = renderPage({
        language, state, nonce, id: row?.id, publicURL: PUBLIC_URL,
        document: row ? JSON.parse(row.document) : null,
        signerName: row?.signer_name, signedAt: row?.signed_at,
      });
      return send(res, row ? 200 : 404, html, {
        "Content-Type": "text/html; charset=utf-8",
        "Content-Security-Policy": `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; img-src 'self' data:; connect-src 'self'; frame-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`,
        "X-Frame-Options": "DENY",
      });
    }
    return send(res, 405, "Method not allowed");
  }
  return send(res, 404, { error: "not found" });
}

export function start(port = PORT) {
  const server = createServer((req, res) => {
    handle(req, res).catch((error) => {
      if (!res.headersSent) send(res, error.status ?? 500, { error: error.status ? error.message : "server error" });
      if (!error.status) console.error(error);
    });
  });
  server.listen(port, "0.0.0.0", () => console.log(`cotiza-sign on :${port}`));
  purge();
  setInterval(() => console.log(`purged ${purge()}`), 3600_000).unref();
  return server;
}

export { purge, db };

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) start();
