// فحص خطوط الموقع محليًا: الخط والوزن الفعليان لكل عنصر، وتحميل الملفات، والقص والتمرير، ومطابقة الآية حرفيًا. QA_URL افتراضيًا 127.0.0.1:4193.
import {chromium} from "playwright-core";
import {mkdirSync, writeFileSync, readFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
const base = process.env.QA_URL || "http://127.0.0.1:4193", out = process.env.QA_OUT || join(tmpdir(), "siyaq-fonts-qa");
const quran = JSON.parse(readFileSync(new URL("../data/quran.json", import.meta.url)));
const canon = id => quran.find(v => v.id === id).text.replace(/﻿/g, "").trim();
mkdirSync(out, {recursive: true});
const browser = await chromium.launch({headless: true, executablePath: process.env.QA_BROWSER || process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"});
const report = {base, at: new Date().toISOString(), runs: []};
const SEL = ["body", ".brand span", "nav a", ".hero h1", ".hero-copy p", ".button", ".review h2", ".search-shell label", "#quote", ".method h2", ".method h3", ".method p", ".result h2", ".tabs button[aria-selected=true]", ".tabs button[aria-selected=false]", ".quran-text", ".context-row p", ".candidate-verse", ".candidate-row h4", ".source-label", ".tafsir-entry h3", ".tafsir-entry p:not(.book-detail)", ".book-detail", ".reading-page h1", ".reading-section h2", ".reading-section p", "footer p", ".word-diff"];
const EXPECT = {quran: [".quran-text", ".context-row p", ".candidate-verse"]};
async function probe(page, label) {
  return page.evaluate(({label, SEL, EXPECT}) => {
    const items = [];
    for (const s of SEL) {
      const el = [...document.querySelectorAll(s)].find(e => e.offsetParent !== null || s === "body"); if (!el) continue;
      const cs = getComputedStyle(el); const fam = cs.fontFamily.split(",")[0].replace(/["']/g, "").trim();
      const faces = [...document.fonts].filter(f => f.family.replace(/["']/g, "") === fam && f.status === "loaded").map(f => f.weight);
      const r = el.getBoundingClientRect();
      const wantQuran = EXPECT.quran.includes(s);
      const famOk = wantQuran ? /amiriquran/i.test(fam.replace(/[^a-z]/gi, "")) : /scheherazade/i.test(fam);
      items.push({sel: s, family: fam, famOk, weight: cs.fontWeight, size: cs.fontSize, lineHeight: cs.lineHeight, loadedWeights: faces, weightLoaded: faces.some(w => w === cs.fontWeight || w.split(" ").length === 2), synthesis: cs.fontSynthesisWeight + "/" + cs.fontSynthesisStyle,
        clipped: (el.scrollWidth > el.clientWidth + 1 && cs.overflowX !== "visible") || (el.scrollHeight > el.clientHeight + 1 && cs.overflowY !== "visible"), offscreen: r.right > innerWidth + 1 || r.left < -1});
    }
    return {label, overflow: document.documentElement.scrollWidth > innerWidth, items};
  }, {label, SEL, EXPECT});
}
for (const [vp, w, h, mobile] of [["desktop", 1366, 900, false], ["mobile", 390, 844, true]]) {
  const ctx = await browser.newContext({viewport: {width: w, height: h}, deviceScaleFactor: 2, isMobile: mobile, hasTouch: mobile, locale: "ar"});
  const page = await ctx.newPage(); const errors = [], fonts = new Set(), external = new Set();
  page.on("pageerror", e => errors.push(String(e)));
  page.on("request", r => {const u = r.url(); if (/\.(woff2?|ttf|otf)(\?|$)/.test(u)) fonts.add(u.split("/").pop()); if (!u.startsWith(base) && !u.startsWith("data:")) external.add(new URL(u).host);});
  const run = {viewport: vp, probes: [], verses: {}, errors, fonts: [], external: []};
  const shot = (name, loc) => (loc ?? page).screenshot({path: `${out}/${vp}-${name}.png`, ...(loc ? {} : {fullPage: false})});
  const ready = async () => {await page.evaluate(() => document.fonts.ready); await page.waitForTimeout(250);};
  await page.goto(base + "/", {waitUntil: "networkidle"}); await ready();
  run.probes.push(await probe(page, "home")); await shot("1-الرئيسية");
  await page.screenshot({path: `${out}/${vp}-1-الرئيسية-كاملة.png`, fullPage: true});
  const search = async q => {await page.locator("#quote").fill(q); await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click(); await page.locator("#result").waitFor(); await ready();};
  await page.locator("#review").scrollIntoViewIfNeeded(); await page.locator("#quote").fill("لا تقربوا الصلاة"); await ready();
  await shot("2-البحث", page.locator("#review"));
  await search("لا تقربوا الصلاة");
  run.verses["4:43"] = (await page.getByTestId("canonical-verse").first().innerText()).replace(/﻿/g, "").trim() === canon("4:43");
  run.probes.push(await probe(page, "verse")); await shot("3-الآية", page.locator("#result"));
  await page.getByRole("tab", {name: "السياق المحيط"}).click(); await ready();
  run.probes.push(await probe(page, "context")); await shot("4-السياق", page.locator("#result"));
  await page.getByRole("tab", {name: "التفسير ومصدره"}).click(); await ready();
  run.probes.push(await probe(page, "tafsir")); await shot("5-التفسير", page.locator("#result"));
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await search("فبأي آلاء ربكما تكذبان");
  run.probes.push(await probe(page, "choices")); await shot("6-المواضع", page.locator("#result"));
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await search("ولا تقربوا الصلوه وانتم سكري حتي تعلموا ما تقولون"); await page.locator(".candidate-row button").first().click(); await page.locator(".difference-paper").waitFor(); await ready();
  run.probes.push(await probe(page, "possible"));
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  await search("الحمد لله رب العالمين الرحمن الرحيم");
  run.verses["1:2+1:3"] = (await page.getByTestId("canonical-verse").allInnerTexts()).map(t => t.replace(/﻿/g, "").trim()).join("|") === [canon("1:2"), canon("1:3")].join("|");
  await page.getByRole("button", {name: /العودة للبحث/}).click();
  // آية فيها علامات وقف (ۚ ۗ) لفحص الرسم
  await search("وإن كنتم مرضى أو على سفر أو جاء أحد منكم من الغائط");
  await shot("7-علامات-الوقف", page.locator(".reading-sheet").first());
  for (const [path, name] of [["/sources", "8-المصادر"], ["/methodology", "9-المنهجية"], ["/support", "10-الدعم"], ["/privacy", "11-الخصوصية"], ["/no-such-page", "12-غير-موجودة"]]) {
    await page.goto(base + path, {waitUntil: "networkidle"}); await ready();
    run.probes.push(await probe(page, path)); await page.screenshot({path: `${out}/${vp}-${name}.png`, fullPage: true});
  }
  run.fonts = [...fonts]; run.external = [...external];
  report.runs.push(run); await ctx.close();
}
writeFileSync(`${out}/فحص-الخطوط.json`, JSON.stringify(report, null, 1));
let failed = false;
for (const r of report.runs) {
  const issues = [];
  for (const p of r.probes) {if (p.overflow) issues.push(`${p.label}:تمرير-أفقي`); for (const i of p.items) {if (!i.famOk && i.sel !== "body" || i.sel === "body" && !/scheherazade/i.test(i.family)) issues.push(`${p.label}:${i.sel}:خط=${i.family}`); if (!i.weightLoaded) issues.push(`${p.label}:${i.sel}:وزن${i.weight}غير-محمّل`); if (i.clipped) issues.push(`${p.label}:${i.sel}:قص`); if (i.offscreen) issues.push(`${p.label}:${i.sel}:خارج`); if (i.synthesis !== "none/none") issues.push(`${p.label}:${i.sel}:synthesis=${i.synthesis}`);}}
  failed ||= issues.length > 0 || r.errors.length > 0 || r.external.length > 0 || r.fonts.length !== 4 || !Object.values(r.verses).every(Boolean);
  console.log(r.viewport, "آيات مطابقة:", JSON.stringify(r.verses), "| ملفات الخط:", r.fonts.join(" "), "| مضيفات خارجية:", r.external.join(" ") || "لا", "| أخطاء JS:", r.errors.length, "|", issues.length ? [...new Set(issues)].join(" ; ") : "OK");
}
await browser.close();
if (failed) process.exitCode = 1;
