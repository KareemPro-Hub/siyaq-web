// فحص متصفح محلي لرحلات التسليم (لا يلمس الموقع المنشور). QA_URL افتراضيًا 127.0.0.1:4192.
import {chromium} from "playwright-core";
import {existsSync, mkdirSync, writeFileSync} from "node:fs";
const base = process.env.QA_URL || "http://127.0.0.1:4192", out = process.env.QA_OUT || ".qa/delivery";
const assets = process.env.QA_ASSETS || out;
mkdirSync(out, {recursive: true});
let browser = await chromium.launch({executablePath: process.env.QA_BROWSER || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true});
// عينات واضحة مستقلة للقراءة، تُحفظ في مجلد الفحص ويمكن إعادة استعمالها.
mkdirSync(assets, {recursive: true});
if (!existsSync(`${assets}/quote.png`)) {
  const fixture = await browser.newPage({viewport: {width: 1100, height: 300}});
  await fixture.setContent('<html lang="ar" dir="rtl"><body style="margin:0;background:white;padding:55px;font:64px Arial;color:black"><p>لا تقربوا الصلاة</p></body></html>');
  await fixture.screenshot({path: `${assets}/quote.png`});
  await fixture.close();
}
if (!existsSync(`${assets}/tiny.gif`)) writeFileSync(`${assets}/tiny.gif`, Buffer.from("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", "base64"));
if (!existsSync(`${assets}/broken.png`)) writeFileSync(`${assets}/broken.png`, "not an image");
const results = []; const ok = (name, pass, detail = "") => {results.push({name, pass: !!pass, detail}); console.log(pass ? "PASS" : "FAIL", name, detail);};
async function open(vp, opts = {}) {
  const [w, h, mobile] = vp === "mobile" ? [390, 844, true] : [1366, 900, false];
  const ctx = await browser.newContext({viewport: {width: w, height: h}, deviceScaleFactor: 2, isMobile: mobile, hasTouch: mobile, locale: "ar", ...opts});
  const page = await ctx.newPage(); const errors = []; page.on("pageerror", e => errors.push(String(e)));
  await page.goto(base + "/", {waitUntil: "networkidle"});
  return {ctx, page, errors};
}
async function search(page, text) {
  await page.locator("#quote").fill(text);
  await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click();
  await page.locator("#result").waitFor({timeout: 20000});
}
for (const vp of ["desktop", "mobile"]) {
  const {ctx, page, errors} = await open(vp);
  await ctx.grantPermissions(["clipboard-read", "clipboard-write"], {origin: base});
  // ١ بحث نصي ومطابقة مؤكدة + التبويبات والروابط والنسخ
  await search(page, "لا تقربوا الصلاة");
  ok(`${vp}: النساء٤٣ مطابقة`, (await page.locator("#result h2").innerText()).includes("في موضعه"));
  ok(`${vp}: رابط الآية`, await page.getByTestId("verse-source-link").getAttribute("href") === "https://quranpedia.net/surah/1/4/43");
  await page.getByRole("tab", {name: "النص القرآني"}).focus(); await page.keyboard.press("ArrowLeft");
  ok(`${vp}: لوحة المفاتيح تنقل بين التبويبات`, await page.getByRole("tab", {name: "السياق المحيط"}).getAttribute("aria-selected") === "true");
  await page.keyboard.press("ArrowLeft");
  const tafsirLinks = await page.getByTestId("tafsir-source-link").evaluateAll(a => a.map(x => x.getAttribute("href")));
  ok(`${vp}: روابط تفسير النساء٤٣ بالكتاب والموضع`, tafsirLinks.length > 0 && tafsirLinks.every(h => /^https:\/\/quranpedia\.net\/tafsir\/an-nisa\/43\?book=(269|27758)$/.test(h)), tafsirLinks.join(" "));
  await page.screenshot({path: `${out}/${vp}-1-النساء43-التفسير.png`, fullPage: false});
  await page.getByRole("tab", {name: "النص القرآني"}).click();
  await page.getByRole("button", {name: "نسخ النص والمرجع"}).click();
  const clip = await page.evaluate(() => navigator.clipboard.readText()).catch(() => "");
  ok(`${vp}: النسخ يشمل النص والمرجع والرابط`, clip.includes("سورة النساء") && clip.includes("quranpedia.net/surah/1/4/43"));
  // ٢ عدة آيات
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await search(page, "الحمد لله رب العالمين الرحمن الرحيم");
  ok(`${vp}: اقتباس من آيتين`, (await page.getByTestId("verse-source-link").count()) === 2);
  // ٣ تعدد المواضع دون اختيار تلقائي
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await search(page, "فبأي آلاء ربكما تكذبان");
  ok(`${vp}: تعدد المواضع بلا اختيار تلقائي`, (await page.locator("#result h2").innerText()).includes("نتيجة البحث") && (await page.locator(".candidate-row").count()) === 12);
  await page.locator(".candidate-row button").first().click();
  await page.getByTestId("canonical-verse").first().waitFor();
  ok(`${vp}: اختيار موضع يعرضه`, (await page.locator(".source-label").first().innerText()).includes("الرحمن"));
  // ٤ التشابه ليس مطابقة
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await search(page, "ولا تقربوا الصلوه وانتم سكري حتي تعلموا ما تقولون");
  ok(`${vp}: التشابه يظهر كاحتمال`, (await page.locator("#choice-title").innerText()).includes("متشابهة"));
  await page.locator(".candidate-row button").first().click();
  await page.locator(".difference-paper").waitFor();
  ok(`${vp}: بعد الاختيار يبقى «محتمل» مع مقارنة الألفاظ`, (await page.locator("#result h2").innerText()).includes("محتمل"));
  // ٥ لا نتيجة
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await search(page, "هذا نص عادي ليس من القرآن الكريم للتجربة");
  ok(`${vp}: غياب النتيجة`, (await page.locator("#choice-title").innerText()).includes("لم نعثر"));
  // ٦ إبراهيم٤٢ و٤٣
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await search(page, "ولا تحسبن الله غافلا عما يعمل الظالمون");
  await page.getByRole("tab", {name: "التفسير ومصدره"}).click();
  ok(`${vp}: إبراهيم٤٢ يصرح بالغياب ويحيل لمقطعه`, await page.getByTestId("dorar-tafsir-passage").getAttribute("href") === "https://dorar.net/tafseer/14/11" && (await page.getByTestId("tafsir-missing").innerText()).includes("لم نعرض تفسير آية أخرى"));
  await page.screenshot({path: `${out}/${vp}-2-إبراهيم42.png`});
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await search(page, "مهطعين مقنعي رءوسهم");
  await page.getByRole("tab", {name: "التفسير ومصدره"}).click();
  const ib = await page.getByTestId("tafsir-source-link").evaluateAll(a => a.map(x => x.getAttribute("href")));
  ok(`${vp}: إبراهيم٤٣ بالكتابين والموضع`, ib.length === 4 && ib.every(h => /^https:\/\/quranpedia\.net\/tafsir\/ibrahim\/43\?book=(269|27758)$/.test(h)) && ib.some(h => h.endsWith("27758")), ib.join(" "));
  // ٧ تجاوز أفقي
  ok(`${vp}: لا تمرير أفقي`, await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  ok(`${vp}: لا أخطاء JavaScript`, errors.length === 0, errors.join(" | "));
  await ctx.close();
}
// ٨ حالات الخطأ والاتصال (كمبيوتر)
{
  const {ctx, page} = await open("desktop");
  let calls = 0;
  await page.route("**/api/review", route => {calls++; return route.abort("internetdisconnected");});
  await page.locator("#quote").fill("لا تقربوا الصلاة");
  await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click();
  await page.getByRole("button", {name: "إعادة المحاولة"}).waitFor();
  ok("فشل الاتصال: رسالة واضحة وإعادة محاولة والنص محفوظ", (await page.locator("#feedback").innerText()).includes("اقتباسك محفوظ") && await page.locator("#quote").inputValue() === "لا تقربوا الصلاة");
  await page.screenshot({path: `${out}/desktop-3-فشل-الاتصال.png`});
  await page.unroute("**/api/review");
  await page.getByRole("button", {name: "إعادة المحاولة"}).click();
  await page.locator("#result").waitFor();
  ok("إعادة المحاولة تكمل البحث بعد عودة الاتصال", (await page.locator("#result h2").innerText()).includes("في موضعه"));
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await page.route("**/api/review", route => route.fulfill({status: 503, contentType: "text/html", body: "<html>down</html>"}));
  await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click();
  await page.getByRole("button", {name: "إعادة المحاولة"}).waitFor();
  ok("تعطل الخدمة (503 HTML) لا يُعرض كـ«لم نجد»", (await page.locator("#feedback").innerText()).includes("لم نحكم") && !(await page.locator("#result").count()));
  await page.unroute("**/api/review");
  await page.route("**/api/review", async route => {calls++; await new Promise(r => setTimeout(r, 800)); await route.continue().catch(() => {});});
  calls = 0;
  await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click();
  // أثناء الانتظار: نقرات وإرسال مباشر للنموذج مرة أخرى
  await page.evaluate(() => {const f = document.querySelector("form.search-shell"); const b = f.querySelector("button[type=submit]"); b.click(); b.click(); f.requestSubmit();});
  await page.locator("#result").waitFor();
  ok("منع الإرسال المكرر", calls === 1, `requests=${calls}`);
  await page.unroute("**/api/review");
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await ctx.setOffline(true);
  await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click();
  ok("بلا إنترنت: رسالة صريحة", (await page.locator("#feedback").innerText()).includes("لا يوجد اتصال"));
  await ctx.setOffline(false);
  await page.route("**/api/review", () => {/* لا رد: يحاكي اتصالًا معلقًا */});
  await page.getByRole("button", {name: "إعادة المحاولة"}).click();
  await page.getByText("استغرقت المراجعة وقتًا أطول").waitFor({timeout: 20000});
  ok("المهلة: رسالة اتصال ضعيف وإعادة محاولة", await page.getByRole("button", {name: "إعادة المحاولة"}).isVisible());
  await ctx.close();
}
// ٩ قراءة الصور
{
  const {ctx, page, errors} = await open("desktop");
  let reviews = 0; page.on("request", r => {if (r.url().endsWith("/api/review")) reviews++;});
  const t0 = Date.now();
  await page.locator('input[type=file]').setInputFiles(`${assets}/quote.png`);
  await page.waitForFunction(() => document.querySelector("#quote")?.value.length > 5, null, {timeout: 120000});
  const ocrCold = Date.now() - t0;
  const text = await page.locator("#quote").inputValue();
  ok("قراءة صورة تملأ مربع النص دون بحث تلقائي", text.includes("الصلاة") && reviews === 0, `«${text}» ${ocrCold}ms`);
  await page.screenshot({path: `${out}/desktop-4-قراءة-صورة.png`});
  await page.locator("#quote").fill(text.trim() + "");
  await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click();
  await page.locator("#result").waitFor();
  ok("تعديل النص المقروء ثم البحث", reviews === 1);
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  const t1 = Date.now();
  await page.locator('input[type=file]').setInputFiles(`${assets}/quote.png`);
  await page.getByText("استُخرج النص").waitFor({timeout: 120000});
  const ocrWarm = Date.now() - t1;
  ok("قراءة ثانية (أصول مخزنة)", true, `${ocrWarm}ms`);
  results.push({name: "ocr-ms", cold: ocrCold, warm: ocrWarm});
  await page.locator('input[type=file]').setInputFiles(`${assets}/tiny.gif`);
  await page.getByText("اختر صورة PNG أو JPEG أو WebP.").waitFor();
  ok("نوع غير مدعوم: رسالة والكتابة متاحة", !(await page.locator("#quote").isDisabled()));
  await page.locator('input[type=file]').setInputFiles(`${assets}/broken.png`);
  await page.getByText("تعذر فتح هذه الصورة").waitFor();
  ok("صورة تالفة: رسالة واضحة", true);
  await ctx.close();
  const c2 = await open("desktop");
  await c2.page.route("**/ocr/**", r => r.abort("internetdisconnected"));
  await c2.page.locator('input[type=file]').setInputFiles(`${assets}/quote.png`);
  await c2.page.getByText("تعذر تحميل قارئ الصور").waitFor({timeout: 60000});
  ok("تعذر تحميل أصول القراءة: رسالة اتصال والكتابة متاحة", !(await c2.page.locator("#quote").isDisabled()));
  await c2.page.screenshot({path: `${out}/desktop-5-تعذر-تحميل-القارئ.png`});
  await c2.ctx.close();
  ok("صور: لا أخطاء JavaScript", errors.length === 0, errors.join(" | "));
}
// حرّر عمليات القارئ المخفية قبل فحص الوصول على الأجهزة محدودة الذاكرة.
await browser.close();
browser = await chromium.launch({executablePath: process.env.QA_BROWSER || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true});
// ١٠ الوصول: التركيز، الحوار، تقليل الحركة، التكبير
{
  const {ctx, page} = await open("desktop", {reducedMotion: "reduce"});
  await page.keyboard.press("Tab");
  ok("أول تركيز رابط «انتقل إلى المحتوى»", (await page.evaluate(() => document.activeElement?.textContent)) === "انتقل إلى المحتوى");
  const about = page.locator("header").getByRole("button", {name: "عن سِياق"});
  await about.click(); await page.keyboard.press("Escape");
  ok("حوار «عن سِياق» يُغلق بـEsc ويعيد التركيز", await about.evaluate(b => document.activeElement === b));
  ok("تقليل الحركة يوقف إضاءة الإطار", (await page.locator(".search-shell").evaluate(e => getComputedStyle(e, "::before").animationName)) === "none");
  const unnamed = await page.evaluate(() => [...document.querySelectorAll("button,a")].filter(e => e.offsetParent !== null && !(e.getAttribute("aria-label") || e.textContent?.trim())).length);
  ok("كل زر ورابط ظاهر له اسم", unnamed === 0, `unnamed=${unnamed}`);
  await ctx.close();
  for (const [w, label] of [[320, "320px"], [683, "تكبير ٢٠٠٪ لشاشة 1366"]]) {
    const c = await browser.newContext({viewport: {width: w, height: 800}, locale: "ar"}); const p = await c.newPage();
    for (const path of ["/", "/sources", "/methodology", "/support", "/privacy"]) { await p.goto(base + path, {waitUntil: "networkidle"}); if (await p.evaluate(() => document.documentElement.scrollWidth > innerWidth)) ok(`تجاوز أفقي ${label} ${path}`, false); }
    await p.goto(base + "/"); await p.locator("#quote").fill("مهطعين مقنعي رءوسهم"); await p.getByRole("button", {name: "راجع الاقتباس", exact: true}).click(); await p.locator("#result").waitFor();
    for (const tab of ["السياق المحيط", "التفسير ومصدره"]) { await p.getByRole("tab", {name: tab}).click(); }
    ok(`لا تجاوز أفقي عند ${label}`, await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    if (w === 320) await p.screenshot({path: `${out}/mobile320-6-التفسير.png`, fullPage: true});
    await c.close();
  }
}
writeFileSync(`${out}/نتائج-الفحص.json`, JSON.stringify({base, at: new Date().toISOString(), results}, null, 1));
console.log("summary", results.filter(r => r.pass === false).length, "failed of", results.filter(r => "pass" in r).length);
await browser.close();
if (results.some(r => r.pass === false)) process.exitCode = 1;
