import test from "node:test";
import assert from "node:assert/strict";
import {NextRequest} from "next/server";
import {POST as review} from "../src/app/api/review/route";
import {POST as explain} from "../src/app/api/explain/route";
import {proxy} from "../src/proxy";

const big = "ا ".repeat(6000);
function streamed(body: string) {
  // جسم بلا Content-Length (تدفق) للتأكد من أن الحد يُطبَّق أثناء القراءة لا بعدها.
  const bytes = new TextEncoder().encode(body);
  const stream = new ReadableStream({start(c) {for (let i = 0; i < bytes.length; i += 1024) c.enqueue(bytes.slice(i, i + 1024)); c.close();}});
  return new Request("http://localhost/api/review", {method: "POST", headers: {"Content-Type": "application/json"}, body: stream, duplex: "half"} as RequestInit);
}

test("review rejects oversized bodies, declared or streamed, with 413", async () => {
  let r = await review(new Request("http://localhost/api/review", {method: "POST", headers: {"Content-Type": "application/json", "Content-Length": "999999"}, body: JSON.stringify({quote: "لا تقربوا الصلاة"})}));
  assert.equal(r.status, 413);
  r = await review(streamed(JSON.stringify({quote: big})));
  assert.equal(r.status, 413);
  assert.equal(r.headers.get("cache-control"), "no-store");
  r = await explain(streamed(JSON.stringify({quote: big})));
  assert.equal(r.status, 413);
});

test("review keeps its contract for valid, invalid and user-facing errors", async () => {
  const ok = await review(streamed(JSON.stringify({quote: "لا تقربوا الصلاة"})));
  assert.equal(ok.status, 200);
  const data = await ok.json();
  assert.equal(data.status, "matched");
  assert.equal(data.selected.id, "4:43");
  const short = await review(new Request("http://localhost/api/review", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({quote: "لا"})}));
  assert.equal(short.status, 400);
  assert.match((await short.json()).error, /كلمتين/);
  const type = await review(new Request("http://localhost/api/review", {method: "POST", headers: {"Content-Type": "text/plain"}, body: "x"}));
  assert.equal(type.status, 415);
  const bad = await review(new Request("http://localhost/api/review", {method: "POST", headers: {"Content-Type": "application/json"}, body: "{"}));
  assert.equal(bad.status, 400);
  const wrongSelection = await review(new Request("http://localhost/api/review", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({quote: "لا تقربوا الصلاة", selection: "2:255"})}));
  assert.equal(wrongSelection.status, 400);
});

test("proxy caches static assets only, and allows indexing of approved pages on the main domain only", () => {
  // الطلب الحقيقي يحمل ترويسة Host؛ نمررها كما يرسلها المتصفح.
  const req = (url: string) => new NextRequest(url, {headers: {host: new URL(url).host}});
  const at = (url: string) => proxy(req(url)).headers;
  const www = "https://www.mysiyaq.com";
  for (const path of ["/", "/sources", "/methodology", "/support", "/privacy"]) {
    assert.equal(at(www + path).get("cache-control"), "no-store");
    assert.equal(at(www + path).get("x-robots-tag"), null, path);
  }
  // واجهات الخدمة، والروابط ذات المعاملات، والمسارات غير المعتمدة، والأصول: خارج الفهرسة.
  for (const path of ["/api/review", "/api/explain", "/?q=لا تقربوا الصلاة", "/sources?x=1", "/not-a-page", "/sources/", "/robots.txt", "/sitemap.xml", "/brand/siyaq-share-512.png", "/_next/static/chunks/a.js"]) {
    assert.equal(at(www + path).get("x-robots-tag"), "noindex, nofollow, noarchive", path);
  }
  // رابط Vercel القديم والدومين بلا www والتشغيل المحلي: noindex على كل شيء، دون تحويل.
  for (const host of ["https://siyaq-theta.vercel.app", "https://mysiyaq.com", "http://localhost:3000"]) {
    for (const path of ["/", "/sources", "/api/review"]) {
      const r = proxy(req(host + path));
      assert.equal(r.headers.get("x-robots-tag"), "noindex, nofollow, noarchive", host + path);
      assert.equal(r.headers.get("x-middleware-next"), "1");
      assert.equal(r.headers.get("location"), null);
    }
  }
  assert.equal(at(www + "/api/review").get("cache-control"), "no-store");
  assert.match(at(www + "/ocr/core/tesseract-core-simd-lstm.wasm").get("cache-control") ?? "", /^public, max-age=86400/);
  assert.match(at(www + "/brand/siyaq-logo.png").get("cache-control") ?? "", /^public/);
  assert.equal(at(www + "/_next/static/chunks/a.js").get("cache-control"), null);
});

test("robots.txt and sitemap.xml list only the approved pages on the main domain", async () => {
  const {default: robots} = await import("../src/app/robots");
  const {default: sitemap} = await import("../src/app/sitemap");
  const r = robots();
  assert.deepEqual(r.rules, {userAgent: "*", allow: "/", disallow: "/api/"});
  assert.equal(r.sitemap, "https://www.mysiyaq.com/sitemap.xml");
  assert.deepEqual(sitemap().map(e => e.url), ["https://www.mysiyaq.com/", "https://www.mysiyaq.com/sources", "https://www.mysiyaq.com/methodology", "https://www.mysiyaq.com/support", "https://www.mysiyaq.com/privacy"]);
});
