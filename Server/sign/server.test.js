// node --test Server/sign
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const dir = mkdtempSync(join(tmpdir(), "cotiza-sign-"));
process.env.DATA_DIR = dir;
process.env.PUBLIC_URL = "https://example.test";
const { start, purge, db } = await import("./server.js");

let server, base;
before(async () => {
  server = start(0);
  await new Promise((r) => server.once("listening", r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => { server.close(); rmSync(dir, { recursive: true, force: true }); });

const secret = "s".repeat(43);
const pdf = Buffer.from("%PDF-1.7\n% test\n").toString("base64");
const document = {
  businessName: "López Painting LLC", kindLabel: "Estimate", number: "E-1003", title: "Interior painting <b>",
  clientName: "Maria Lopez", dateText: "November 12, 2026", validUntilText: "December 12, 2026",
  items: [{ text: "Paint bedrooms", detail: "3 × $450.00", amount: "$1,350.00" }],
  totals: [{ label: "Subtotal", value: "$1,886.84" }], total: "$1,915.20", terms: "50% deposit.",
};
// A 1x1 transparent PNG, padded past the minimum size the server accepts.
const png = "data:image/png;base64," + Buffer.concat([
  Buffer.from("89504e470d0a1a0a0000000d4948445200000001000000010806000000", "hex"), Buffer.alloc(120),
]).toString("base64");

async function create(body = { language: "es", document, pdf }, headers = { "X-Cotiza-Secret": secret }) {
  return fetch(`${base}/api/v1/sign-requests`, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });
}

test("the app creates a link and the client sees the estimate, escaped", async () => {
  const res = await create();
  assert.equal(res.status, 201);
  const { id, url } = await res.json();
  assert.match(id, /^[A-Za-z0-9_-]{22}$/);
  assert.equal(url, `https://example.test/s/${id}`);
  const page = await fetch(`${base}/s/${id}`);
  assert.equal(page.status, 200);
  assert.match(page.headers.get("content-security-policy"), /script-src 'nonce-/);
  const html = await page.text();
  assert.match(html, /Aprobar esta cotización/);
  assert.match(html, /Interior painting &lt;b&gt;/);
  assert.match(html, /\$1,915\.20/);
  assert.match(html, /<meta property="og:title" content="Estimate E-1003 · López Painting LLC">/);
  assert.match(html, /og:description" content="Interior painting &lt;b&gt; — Total \$1,915\.20 · Revísela y fírmela en línea"/);
  assert.match(html, /og:image" content="https:\/\/example\.test\/s\/card-es\.png"/);
  const card = await fetch(`${base}/s/card-es.png`);
  assert.equal(card.headers.get("content-type"), "image/png");
  assert.ok((await card.arrayBuffer()).byteLength > 10_000);
  const file = await fetch(`${base}/s/${id}/document.pdf`);
  assert.equal(file.headers.get("content-type"), "application/pdf");
});

test("a Turkish estimate gets the Turkish page and card", async () => {
  const res = await create({ language: "tr", document, pdf });
  assert.equal(res.status, 201);
  const { id } = await res.json();
  const html = await (await fetch(`${base}/s/${id}`)).text();
  assert.match(html, /<html lang="tr">/);
  assert.match(html, /Bu teklifi onaylayın/);
  assert.match(html, /og:image" content="https:\/\/example\.test\/s\/card-tr\.png"/);
  const card = await fetch(`${base}/s/card-tr.png`);
  assert.equal(card.headers.get("content-type"), "image/png");
  // An unknown language falls back to English.
  const other = await (await create({ language: "xx", document, pdf })).json();
  assert.match(await (await fetch(`${base}/s/${other.id}`)).text(), /Approve this estimate/);
});

test("bad uploads are refused", async () => {
  assert.equal((await create({ document, pdf }, {})).status, 400);
  assert.equal((await create({ document, pdf: Buffer.from("not a pdf").toString("base64") })).status, 400);
  assert.equal((await create({ document: { title: "x" }, pdf })).status, 400);
});

test("signing approves once; the app reads it with its secret only, then deletes it", async () => {
  const { id } = await (await create()).json();
  const status = (s = secret) => fetch(`${base}/api/v1/sign-requests/${id}`, { headers: { "X-Cotiza-Secret": s } });
  assert.equal((await (await status()).json()).status, "pending");
  assert.equal((await status("x".repeat(43))).status, 404);

  const sign = (body) => fetch(`${base}/s/${id}/sign`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  assert.equal((await sign({ name: "Maria", signature: png })).status, 400, "consent required");
  assert.equal((await sign({ name: "Maria", signature: "data:image/png;base64,AAAA", agree: true })).status, 400);
  assert.equal((await sign({ name: "Maria Lopez", signature: png, agree: true })).status, 200);
  assert.equal((await sign({ name: "Someone else", signature: png, agree: true })).status, 409);

  const signed = await (await status()).json();
  assert.equal(signed.status, "signed");
  assert.equal(signed.signerName, "Maria Lopez");
  assert.ok(Buffer.from(signed.signature, "base64").subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47])));
  assert.match(await (await fetch(`${base}/s/${id}`)).text(), /Aprobada/);

  assert.equal((await fetch(`${base}/api/v1/sign-requests/${id}`, { method: "DELETE", headers: { "X-Cotiza-Secret": secret } })).status, 204);
  assert.equal((await status()).status, 404);
  assert.equal((await fetch(`${base}/s/${id}`)).status, 404);
});

test("expired requests are purged with their PDF", async () => {
  const { id } = await (await create()).json();
  db.prepare("UPDATE requests SET expires_at = ? WHERE id = ?").run(Date.now() - 1, id);
  assert.match(await (await fetch(`${base}/s/${id}`)).text(), /venció/);
  assert.ok(purge() >= 1);
  assert.equal((await fetch(`${base}/s/${id}/document.pdf`)).status, 404);
});
