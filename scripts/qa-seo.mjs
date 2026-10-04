// فحص الفهرسة محليًا بعد `npm run build && npm run start`: ترويسة X-Robots-Tag لكل مضيف ومسار، والعنوان والوصف والرابط الأساسي،
// وrobots.txt وsitemap.xml، وأن البحث لا يضع الاقتباس في رابط الصفحة أو في رابط أي طلب. QA_URL افتراضيًا 127.0.0.1:4194.
// المضيف يُمرَّر بترويسة Host، فيُختبر سلوك www.mysiyaq.com ورابط Vercel القديم دون لمس الموقع المنشور.
import http from "node:http";
import {writeFileSync} from "node:fs";
import {chromium} from "playwright-core";
const base = new URL(process.env.QA_URL || "http://127.0.0.1:4194"), out = process.env.QA_OUT || "/tmp/siyaq-seo-qa.json";
const browserPath = process.env.QA_BROWSER || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const WWW = "www.mysiyaq.com", NOINDEX = "noindex, nofollow, noarchive";
const APPROVED = ["/", "/sources", "/methodology", "/support", "/privacy"];
const results = []; let failed = 0;
const check = (name, ok, detail = "") => {results.push({name, ok, detail}); if (!ok) failed++; console.log(`${ok ? "PASS" : "FAIL"} ${name} ${detail}`);};
// fetch يمنع تغيير Host، لذلك نستعمل http مباشرة.
const get = (path, host, method = "GET", body) => new Promise((res, rej) => {
  const req = http.request({hostname: base.hostname, port: base.port, path, method, headers: {host, ...(body ? {"content-type": "application/json"} : {})}}, r => {let d = ""; r.setEncoding("utf8"); r.on("data", c => d += c); r.on("end", () => res({status: r.statusCode, headers: r.headers, body: d}));});
  req.on("error", rej); if (body) req.write(body); req.end();
});
const meta = (html, re) => (html.match(re) || [])[1];

for (const path of APPROVED) {
  const r = await get(path, WWW);
  const canonical = meta(r.body, /<link rel="canonical" href="([^"]+)"/);
  const want = path === "/" ? "https://www.mysiyaq.com" : `https://www.mysiyaq.com${path}`;
  check(`www ${path}: مسموح بالفهرسة`, r.status === 200 && !r.headers["x-robots-tag"] && !/<meta name="robots"/.test(r.body), `status=${r.status} x-robots-tag=${r.headers["x-robots-tag"] ?? "-"}`);
  check(`www ${path}: عنوان ووصف ورابط أساسي`, !!meta(r.body, /<title>([^<]+)<\/title>/) && !!meta(r.body, /<meta name="description" content="([^"]+)"/) && canonical === want, `canonical=${canonical}`);
  check(`www ${path}: بلا Gmail أو رابط Vercel`, !/[\w.]+@gmail\.com/i.test(r.body) && !/vercel\.app/.test(r.body));
}
for (const path of ["/api/review", "/?q=%D9%84%D8%A7%20%D8%AA%D9%82%D8%B1%D8%A8%D9%88%D8%A7", "/sources?ref=x", "/not-a-page", "/robots.txt", "/sitemap.xml"]) {
  const r = await get(path, WWW);
  check(`www ${decodeURIComponent(path)}: خارج الفهرسة`, r.headers["x-robots-tag"] === NOINDEX, `status=${r.status}`);
}
const api = await get("/api/review", WWW, "POST", JSON.stringify({quote: "لا تقربوا الصلاة"}));
check("خدمة المراجعة: تعمل وno-store وnoindex", api.status === 200 && api.headers["cache-control"] === "no-store" && api.headers["x-robots-tag"] === NOINDEX);
for (const host of ["siyaq-theta.vercel.app", "mysiyaq.com"]) {
  for (const path of APPROVED) {
    const r = await get(path, host);
    check(`${host} ${path}: noindex دون تحويل`, r.status === 200 && r.headers["x-robots-tag"] === NOINDEX && !r.headers.location);
  }
  const a = await get("/api/review", host, "POST", JSON.stringify({quote: "لا تقربوا الصلاة"}));
  check(`${host}: خدمة الآيفون تعمل دون تحويل`, a.status === 200 && JSON.parse(a.body).status === "matched");
}
const robots = (await get("/robots.txt", WWW)).body;
check("robots.txt", robots.includes("Allow: /") && robots.includes("Disallow: /api/") && robots.includes("Sitemap: https://www.mysiyaq.com/sitemap.xml"), JSON.stringify(robots));
const locs = [...(await get("/sitemap.xml", WWW)).body.matchAll(/<loc>([^<]+)<\/loc>/g)].map(m => m[1]);
check("sitemap.xml: الصفحات المعتمدة فقط", JSON.stringify(locs) === JSON.stringify(APPROVED.map(p => `https://www.mysiyaq.com${p}`)), locs.join(" "));

// البحث في المتصفح: النتيجة حالة داخل الصفحة، والاقتباس لا يظهر في الرابط ولا في رابط أي طلب.
const browser = await chromium.launch({executablePath: browserPath});
const page = await browser.newPage({extraHTTPHeaders: {}});
const urls = [];
page.on("request", q => urls.push(q.url()));
await page.goto(base.href, {waitUntil: "networkidle"});
const before = page.url();
await page.locator("#quote").fill("لا تقربوا الصلاة وأنتم سكارى");
await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click();
await page.waitForSelector(".quran-text", {timeout: 15000});
const quoteInUrls = urls.some(u => {const d = decodeURIComponent(u); return d.includes("تقربوا") || d.includes("سكارى");});
check("البحث لا يغيّر رابط الصفحة", page.url() === before, page.url());
check("الاقتباس لا يظهر في رابط أي طلب", !quoteInUrls, `${urls.length} طلبًا`);
await browser.close();

writeFileSync(out, JSON.stringify({base: base.href, failed, results}, null, 2));
console.log(`summary ${failed} failed of ${results.length}`);
process.exit(failed ? 1 : 0);
