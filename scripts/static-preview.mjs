// يحفظ معاينة HTML مستقلة للنتيجة كما يرسمها الموقع المحلي: الخطوط والصور مضمّنة، دون سكربتات، وكل أقسام النتيجة ظاهرة.
import {chromium} from "playwright-core";
import {writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
const base = process.env.QA_URL || "http://127.0.0.1:4193", out = process.argv[2] || join(tmpdir(), "siyaq-font-preview.html");
const b = await chromium.launch({headless: true, executablePath: process.env.QA_BROWSER || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"});
const p = await (await b.newContext({viewport: {width: 1366, height: 900}, locale: "ar"})).newPage();
await p.goto(base + "/", {waitUntil: "networkidle"});
await p.locator("#quote").fill("لا تقربوا الصلاة");
await p.getByRole("button", {name: "راجع الاقتباس", exact: true}).click();
await p.locator("#result").waitFor(); await p.evaluate(() => document.fonts.ready);
const html = await p.evaluate(async () => {
  const toData = async url => {const r = await fetch(url); const blob = await r.blob(); return await new Promise(res => {const fr = new FileReader(); fr.onload = () => res(fr.result); fr.readAsDataURL(blob);});};
  let css = "";
  for (const sheet of document.styleSheets) {
    let text = ""; for (const rule of sheet.cssRules) text += rule.cssText + "\n";
    const urls = [...new Set([...text.matchAll(/url\("?([^")]+)"?\)/g)].map(m => m[1]).filter(u => !u.startsWith("data:")))];
    for (const u of urls) text = text.split(u).join(await toData(new URL(u, sheet.href || location.href).href));
    css += text;
  }
  for (const img of document.querySelectorAll("img")) {img.src = await toData(img.currentSrc || img.src); img.removeAttribute("srcset"); img.removeAttribute("loading");}
  document.querySelectorAll("script,link[rel=preload],link[rel=stylesheet],noscript").forEach(e => e.remove());
  document.querySelectorAll("[role=tabpanel]").forEach(e => {e.hidden = false; const h = document.createElement("p"); h.className = "eyeline"; h.textContent = "— " + document.getElementById(e.getAttribute("aria-labelledby"))?.textContent + " —"; e.prepend(h);});
  const note = '<p style="background:#fff7e0;padding:8px 16px;margin:0;font:14px Tahoma;text-align:center">معاينة ثابتة محفوظة من النسخة المحلية للموقع بخطَّي شهرزاد الجديد وأميري قرآن. الأقسام الثلاثة للنتيجة معروضة معًا هنا؛ في الموقع تظهر بالتبويبات. لم يُنشر هذا التغيير.</p>';
  document.body.insertAdjacentHTML("afterbegin", note);
  return "<!doctype html>\n" + document.documentElement.outerHTML.replace("<head>", `<head><style>${css}</style>`);
});
writeFileSync(out, html); console.log(out, Math.round(html.length / 1024) + "KB");
await b.close();
