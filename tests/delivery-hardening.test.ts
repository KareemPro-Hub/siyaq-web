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

test("proxy keeps noindex everywhere and caches static assets only", () => {
  const at = (path: string) => proxy(new NextRequest("http://localhost" + path)).headers;
  for (const path of ["/", "/api/review", "/sources"]) {
    assert.equal(at(path).get("cache-control"), "no-store");
    assert.equal(at(path).get("x-robots-tag"), "noindex, nofollow, noarchive");
  }
  assert.match(at("/ocr/core/tesseract-core-simd-lstm.wasm").get("cache-control") ?? "", /^public, max-age=86400/);
  assert.match(at("/brand/siyaq-logo.png").get("cache-control") ?? "", /^public/);
  assert.equal(at("/_next/static/chunks/a.js").get("cache-control"), null);
  assert.equal(at("/_next/static/chunks/a.js").get("x-robots-tag"), "noindex, nofollow, noarchive");
});
