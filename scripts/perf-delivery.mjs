// قياس محلي: بايتات الشبكة والزمن مع شبكة مخنوقة (١٠ ميجابت/ث، ٤٠ مللي ثانية) — أول زيارة، زيارة ثانية، أول قراءة صورة وقراءة بعد إعادة التحميل.
import {chromium} from "playwright-core";
const targets = (process.env.TARGETS || "base=http://127.0.0.1:4191,new=http://127.0.0.1:4192").split(",").map(s => s.split("="));
const img = process.env.QA_IMG || ".qa/delivery/quote.png";
const browser = await chromium.launch({executablePath: process.env.QA_BROWSER || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true});
const report = {};
for (const [name, base] of targets) {
  const ctx = await browser.newContext({viewport: {width: 1366, height: 900}, locale: "ar"});
  const page = await ctx.newPage(); const cdp = await ctx.newCDPSession(page);
  await cdp.send("Network.enable");
  await cdp.send("Network.emulateNetworkConditions", {offline: false, latency: 40, downloadThroughput: 10e6 / 8, uploadThroughput: 5e6 / 8});
  let bytes = 0, reqs = 0; cdp.on("Network.loadingFinished", e => {bytes += e.encodedDataLength; reqs++;});
  const measure = async (label, fn) => {bytes = 0; reqs = 0; const t = Date.now(); await fn(); await page.waitForTimeout(300); report[name] = report[name] || {}; report[name][label] = {ms: Date.now() - t, kb: Math.round(bytes / 1024), requests: reqs};};
  await measure("زيارة أولى", () => page.goto(base + "/", {waitUntil: "load"}));
  await measure("زيارة ثانية", () => page.goto(base + "/", {waitUntil: "load"}));
  const ocr = async () => {await page.locator("input[type=file]").setInputFiles(img); await page.getByText("استُخرج النص").waitFor({timeout: 180000});};
  await measure("أول قراءة صورة", ocr);
  await page.goto(base + "/", {waitUntil: "load"});
  await measure("قراءة بعد إعادة تحميل الصفحة", ocr);
  await measure("بحث نصي", async () => {await page.locator("#quote").fill("لا تقربوا الصلاة"); await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click(); await page.locator("#result").waitFor();});
  await ctx.close();
}
console.log(JSON.stringify(report, null, 1));
await browser.close();
