// فحص متصفح محلي لمساعد سِياق بعد `npm run build && npm run start`. QA_URL افتراضيًا 127.0.0.1:4197.
// مهم: الصوت هنا محاكاة (mock) لـ SpeechRecognition وspeechSynthesis داخل الصفحة. يختبر المنطق والواجهة والإجراءات،
// ولا يُعد تجربة تعرف صوتي حقيقية أو اختبار جودة صوت.
import {chromium} from "playwright-core";
import {mkdirSync, readFileSync, writeFileSync} from "node:fs";
const base = process.env.QA_URL || "http://127.0.0.1:4197", out = process.env.QA_OUT || "/tmp/siyaq-assistant-qa";
mkdirSync(out, {recursive: true});
const content = JSON.parse(readFileSync(new URL("../src/content/assistant-responses.json", import.meta.url), "utf8"));
const M = content.messages, I = Object.fromEntries(content.intents.map(i => [i.id, i]));
const prepared = new Set([...Object.values(M), ...content.intents.flatMap(i => [i.answer, i.spoken].filter(Boolean))]);
const launchBrowser = () => chromium.launch({executablePath: process.env.QA_BROWSER || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true});
let browser = await launchBrowser();
const results = []; const ok = (name, pass, detail = "") => {results.push({name, pass: !!pass, detail}); console.log(pass ? "PASS" : "FAIL", name, detail);};

// محاكاة الصوت. mode: normal | denied | network | none (لا تعرف) | novoice (لا صوت عربي)
function mockSpeech(mode) {
  const log = window.__a = {events: [], speaks: [], recs: 0, mic: 0};
  let speakingNow = false, current = null;
  if (mode !== "nosynth") {
    window.SpeechSynthesisUtterance = class {constructor(t) {this.text = t; this.onend = null; this.onerror = null;}};
    const voices = mode === "novoice" ? [{lang: "en-US", name: "Mock English", localService: true}] : [{lang: "en-US", name: "Mock English"}, {lang: "ar-SA", name: "Mock Arabic", localService: true}];
    Object.defineProperty(window, "speechSynthesis", {configurable: true, value: {
      getVoices: () => voices, addEventListener() {}, removeEventListener() {},
      speak(u) {log.speaks.push(u.text); log.events.push("speak"); speakingNow = true; current = u; setTimeout(() => {if (current === u) {speakingNow = false; current = null; u.onend?.();}}, 400);},
      cancel() {log.events.push("cancel"); speakingNow = false; current = null;},
    }});
  }
  if (mode === "none") {delete window.webkitSpeechRecognition; delete window.SpeechRecognition; Object.defineProperty(window, "webkitSpeechRecognition", {value: undefined}); Object.defineProperty(window, "SpeechRecognition", {value: undefined}); return;}
  class Rec {
    constructor() {this.lang = ""; this.continuous = true; this.interimResults = false; window.__rec = this;}
    start() {log.recs++; log.events.push(speakingNow ? "listen-while-speaking" : "listen"); log.lang = this.lang; log.continuous = this.continuous;
      if (mode === "denied") setTimeout(() => {this.onerror?.({error: "not-allowed"}); this.onend?.();}, 50);
      if (mode === "network") setTimeout(() => {this.onerror?.({error: "network"}); this.onend?.();}, 50);}
    say(text) {this.onresult?.({resultIndex: 0, results: [Object.assign([{transcript: text}], {isFinal: true})]}); this.onend?.();}
    stop() {setTimeout(() => this.onend?.(), 10);}
    abort() {log.events.push("abort"); setTimeout(() => {this.onerror?.({error: "aborted"}); this.onend?.();}, 0);}
  }
  window.SpeechRecognition = Rec; window.webkitSpeechRecognition = Rec;
  const gum = navigator.mediaDevices?.getUserMedia?.bind(navigator.mediaDevices);
  if (gum) navigator.mediaDevices.getUserMedia = (...a) => {log.mic++; return gum(...a);};
}

async function open(vp, mode = "normal", path = "/") {
  const [w, h, mobile] = vp === "mobile" ? [390, 844, true] : vp === "small" ? [320, 640, true] : [1366, 900, false];
  const ctx = await browser.newContext({viewport: {width: w, height: h}, deviceScaleFactor: 2, isMobile: mobile, hasTouch: mobile, locale: "ar"});
  await ctx.addInitScript(mockSpeech, mode);
  const page = await ctx.newPage(); const errors = []; const reviews = [];
  page.on("pageerror", e => errors.push(String(e)));
  page.on("console", m => {if (m.type() === "error") errors.push(m.text());});
  page.on("request", r => {if (r.url().includes("/api/review")) reviews.push(r.postData());});
  await page.goto(base + path, {waitUntil: "networkidle"});
  return {ctx, page, errors, reviews};
}
const launcher = page => page.locator(".assistant-launcher");
const panel = page => page.locator(".assistant-panel[role=dialog]");
const lastAssistant = page => page.locator(".assistant-msg:not(.from-user) > p").last();
async function openPanel(page) {await launcher(page).click(); await panel(page).waitFor(); await page.waitForTimeout(150);}
async function ask(page, text) {const input = page.locator("#assistant-input"); await input.fill(text); await input.press("Enter"); await page.waitForTimeout(120);}
const a = page => page.evaluate(() => window.__a);
const overflow = page => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);

// ١. لا صوت ولا ميكروفون تلقائيًا، ثم الترحيب بعد الضغط
{
  const {ctx, page, errors} = await open("desktop");
  await page.waitForTimeout(500);
  let s = await a(page);
  ok("لا نطق أو استماع أو ميكروفون عند الدخول", s.speaks.length === 0 && s.recs === 0 && s.mic === 0);
  ok("زر «تحدث مع سِياق» ظاهر ومسمّى", await launcher(page).isVisible() && (await launcher(page).innerText()).includes(M.launcher));
  const headers = await page.request.get(base + "/");
  ok("سياسة الأذونات تسمح بالميكروفون للموقع نفسه فقط", (headers.headers()["permissions-policy"] || "").includes("microphone=(self)"));
  await openPanel(page);
  ok("العنوان «مساعد سِياق — تجريبي» والتعريف التجريبي", (await panel(page).locator("h2").innerText()) === M.title && (await panel(page).innerText()).includes(M.notice));
  ok("التركيز ينتقل إلى اللوحة عند الفتح", await page.evaluate(() => document.activeElement?.id === "assistant-title"));
  await page.waitForTimeout(200);
  s = await a(page);
  ok("الترحيب مكتوب ومنطوق بالفصحى", (await page.locator(".assistant-msg p").first().innerText()) === M.welcome && s.speaks[0] === M.welcome, JSON.stringify(s.speaks));
  ok("لا استماع بعد الترحيب دون ضغط «تحدّث»", s.recs === 0 && s.mic === 0);
  ok("توضيح معالجة الصوت قبل الاستخدام", (await panel(page).innerText()).includes(M.voicePrivacy));
  // الأسئلة العشرة من الأزرار
  for (const id of content.starters) {
    if (!(await panel(page).locator(".assistant-chips").isVisible())) await panel(page).getByRole("button", {name: M.moreQuestions}).click();
    await panel(page).locator(".assistant-chips").getByRole("button", {name: I[id].question, exact: true}).click();
    await page.waitForTimeout(80);
    ok(`سؤال: ${I[id].question}`, (await lastAssistant(page).innerText()) === I[id].answer);
  }
  // أسئلة مكتوبة: خارج النطاق وغامضة ومتقاربة
  await ask(page, "ما حكم الغناء ؟");
  ok("سؤال شرعي: بيان حدود المساعدة دون جواب", (await lastAssistant(page).innerText()) === M.outOfScope);
  await ask(page, "طيب");
  ok("طلب غير واضح: طلب توضيح وخيارات", (await lastAssistant(page).innerText()) === M.unclear && await panel(page).locator(".assistant-chips").isVisible());
  await ask(page, "صورة السياق");
  ok("طلب يجمع أمرين: خياران دون تنفيذ", (await lastAssistant(page).innerText()) === M.compound && await page.locator(".assistant-msg").last().locator(".assistant-actions button").count() === 2);
  await ask(page, "ما سياق وهل الخدمة مجانية");
  ok("سؤالان بالوزن نفسه: سؤال توضيحي بخيارين", (await lastAssistant(page).innerText()) === M.clarify && await page.locator(".assistant-msg").last().locator(".assistant-actions button").count() === 2);
  await ask(page, "أريد مراجعة اقتباس ولدي صورة");
  ok("طلب مركب بإجراءين: لا تنفيذ بالتخمين", (await lastAssistant(page).innerText()) === M.compound && await panel(page).isVisible() && await page.evaluate(() => document.activeElement?.id !== "quote"));
  await ask(page, "لا أريد فتح التفسير");
  ok("النفي «لا أريد فتح التفسير»: لا إجراء وخيارات", (await lastAssistant(page).innerText()) === M.negated && await panel(page).locator(".assistant-chips").isVisible());
  const urlBefore = page.url();
  await ask(page, "لا تفتح المصادر");
  ok("النفي «لا تفتح المصادر»: لا انتقال", (await lastAssistant(page).innerText()) === M.negated && page.url() === urlBefore);
  await ask(page, "هل نتائج التشابه مؤكدة ؟");
  ok("صيغة مكتوبة لسؤال قائم", (await lastAssistant(page).innerText()) === I.similarity.answer);
  // التبويب دون نتيجة
  await ask(page, "افتح التفسير");
  ok("طلب التفسير دون نتيجة يشرح الخطوة أولًا", (await lastAssistant(page).innerText()) === M.needResult);
  // Esc يغلق ويعيد التركيز ويوقف النطق
  await ask(page, "ما سِياق ؟");
  const before = (await a(page)).events.filter(e => e === "cancel").length;
  await page.keyboard.press("Escape");
  await page.waitForTimeout(150);
  ok("Esc يغلق اللوحة ويعيد التركيز إلى الزر", !(await panel(page).count()) && await page.evaluate(() => document.activeElement?.classList.contains("assistant-launcher")));
  ok("الإغلاق يوقف النطق", (await a(page)).events.filter(e => e === "cancel").length > before);
  s = await a(page);
  ok("لا يُنطق إلا نص معدّ مسبقًا", s.speaks.every(t => prepared.has(t)), s.speaks.filter(t => !prepared.has(t)).join(" | "));
  ok("لا أخطاء JavaScript (١)", errors.length === 0, errors.join(" | "));
  await ctx.close();
}

// ٢. الإجراءات الفعلية: مربع الاقتباس، الصورة، الصفحات، التبويب
{
  const {ctx, page, errors, reviews} = await open("desktop");
  await openPanel(page);
  await ask(page, "أريد مراجعة اقتباس");
  ok("«أريد مراجعة اقتباس» ينقل التركيز إلى مربع الاقتباس ويغلق اللوحة", await page.evaluate(() => document.activeElement?.id === "quote") && !(await panel(page).count()));
  ok("إشعار مكتوب بعد التنفيذ فقط", (await page.locator(".assistant-toast").innerText()) === M.quoteFocused);
  await openPanel(page);
  await ask(page, "لدي صورة");
  ok("«لدي صورة» يعرض قارئ الصور مع زر الاختيار", (await lastAssistant(page).innerText()) === I.image_how.answer && await page.locator("#image-reader").isVisible());
  const chooser = page.waitForEvent("filechooser", {timeout: 3000}).then(() => true).catch(() => false);
  await page.locator(".assistant-msg").last().getByRole("button", {name: "اختر صورة"}).click();
  ok("زر «اختر صورة» يفتح منتقي الملفات بنقرة المستخدم", await chooser);
  await page.waitForTimeout(100);
  ok("بعد فتح المنتقي تُغلق اللوحة", !(await panel(page).count()));
  await openPanel(page);
  await ask(page, "أريد المصادر");
  await page.waitForURL("**/sources");
  await page.waitForTimeout(250);
  ok("«أريد المصادر» يفتح صفحة المصادر ويؤكد بعد الانتقال", (await lastAssistant(page).innerText()) === I.open_sources.answer && await panel(page).isVisible());
  await ask(page, "افتح صفحة المصادر");
  ok("طلب الصفحة الحالية لا يدّعي انتقالًا", (await lastAssistant(page).innerText()) === M.pageAlready);
  await ask(page, "الخصوصية");
  await page.waitForURL("**/privacy"); await page.waitForTimeout(200);
  ok("«الخصوصية» تفتح صفحة الخصوصية", (await lastAssistant(page).innerText()) === I.open_privacy.answer);
  await ask(page, "افتح صفحة كيف يعمل");
  await page.waitForURL("**/methodology"); await page.waitForTimeout(200);
  ok("«كيف يعمل» تفتح صفحة المنهجية", (await lastAssistant(page).innerText()) === I.open_methodology.answer);
  await ask(page, "افتح صفحة الدعم");
  await page.waitForURL("**/support"); await page.waitForTimeout(200);
  ok("«الدعم» تفتح صفحة الدعم", (await lastAssistant(page).innerText()) === I.open_support.answer);
  await ask(page, "أريد مراجعة اقتباس");
  await page.waitForURL(u => new URL(u).pathname === "/"); await page.locator("#quote").waitFor(); await page.waitForTimeout(400);
  ok("من صفحة أخرى: العودة إلى الرئيسية ثم التركيز في مربع الاقتباس", await page.evaluate(() => document.activeElement?.id === "quote"));
  ok("لم تُرسل أي مراجعة أثناء الإجراءات", reviews.length === 0, String(reviews.length));
  // نتيجة مختارة ثم فتح التبويبات
  await page.locator("#quote").fill("لا تقربوا الصلاة");
  await page.getByRole("button", {name: "راجع الاقتباس", exact: true}).click();
  await page.locator("#result").waitFor();
  const quoteBefore = await page.locator("#quote").inputValue();
  await openPanel(page);
  await ask(page, "افتح التفسير");
  await page.waitForTimeout(250);
  ok("«افتح التفسير» يفتح تبويب التفسير في النتيجة المختارة", await page.locator("#tafsir-tab").getAttribute("aria-selected") === "true" && await page.evaluate(() => document.activeElement?.id === "tafsir-tab"));
  await openPanel(page);
  await ask(page, "افتح السياق");
  await page.waitForTimeout(250);
  ok("«افتح السياق» يفتح تبويب السياق المحيط", await page.locator("#context-tab").getAttribute("aria-selected") === "true");
  ok("المساعد لا يغيّر الاقتباس أو النتيجة", (await page.locator("#quote").inputValue()) === quoteBefore && reviews.length === 1 && (await page.locator("#result h2").innerText()).includes("في موضعه"));
  ok("لا أخطاء JavaScript (٢)", errors.length === 0, errors.join(" | "));
  await ctx.close();
}

// ٣. الصوت (محاكاة): عدم التداخل، الإملاء والتأكيد، الأخطاء
{
  const {ctx, page, errors, reviews} = await open("desktop");
  await openPanel(page);
  await panel(page).getByRole("button", {name: M.talk}).click();
  await page.waitForTimeout(80);
  let s = await a(page);
  ok("الضغط على «تحدّث» أثناء نطق الترحيب يوقف النطق قبل الاستماع", s.events.includes("listen") && !s.events.includes("listen-while-speaking") && s.events.lastIndexOf("cancel") < s.events.indexOf("listen"), s.events.join(","));
  ok("استماع لمرة واحدة بالعربية", s.recs === 1 && /^ar-/.test(s.lang) && s.continuous === false, `${s.lang}`);
  ok("حالة «أستمع…» ظاهرة", (await panel(page).locator(".assistant-status").innerText()).includes(M.listening));
  await page.evaluate(() => window.__rec.say("كيف أستخدم صورة"));
  await page.waitForTimeout(150);
  ok("ما سُمع يظهر نصًا قابلًا للتحقق ثم الرد المعد", (await page.locator(".assistant-msg.from-user").last().innerText()).includes("سمعتُ") && (await lastAssistant(page).innerText()) === I.image_how.answer);
  s = await a(page);
  ok("لا استماع جديد تلقائيًا بعد الرد", s.recs === 1);
  // الإملاء
  await ask(page, "أريد إملاء الاقتباس بصوتي");
  await page.waitForTimeout(500);
  await panel(page).getByRole("button", {name: M.talk}).click();
  await page.evaluate(() => window.__rec.say("لا تقربوا الصلاه"));
  await page.waitForTimeout(150);
  const draft = panel(page).locator("#assistant-draft");
  ok("الإملاء يعرض النص كما سُمع دون تصحيح", (await draft.inputValue()) === "لا تقربوا الصلاه");
  ok("الإملاء لا يرسل مراجعة قبل التأكيد", reviews.length === 0);
  await draft.fill("لا تقربوا الصلاة");
  await panel(page).getByRole("button", {name: M.reviewQuote}).click();
  await page.locator("#result").waitFor({timeout: 20000});
  await page.waitForTimeout(300);
  ok("بعد التأكيد: النص المصحح في المربع ومراجعة واحدة فقط", (await page.locator("#quote").inputValue()) === "لا تقربوا الصلاة" && reviews.length === 1, String(reviews.length));
  // اقتباس قيل مباشرة للمساعد
  await openPanel(page);
  await panel(page).getByRole("button", {name: M.talk}).click();
  await page.evaluate(() => window.__rec.say("إن مع العسر يسرا"));
  await page.waitForTimeout(150);
  ok("نص غير مفهوم كسؤال: توضيح مع خيار وضعه في المربع", (await lastAssistant(page).innerText()) === M.unclear && await panel(page).getByRole("button", {name: M.useHeard}).isVisible());
  await panel(page).getByRole("button", {name: M.useHeard}).click();
  await panel(page).getByRole("button", {name: M.placeQuote}).click();
  await page.waitForTimeout(150);
  ok("مربع الاقتباس فيه نص: سؤال قبل الاستبدال", (await lastAssistant(page).innerText()) === M.replaceAsk && (await page.locator("#quote").inputValue()) === "لا تقربوا الصلاة");
  await page.locator(".assistant-msg").last().getByRole("button", {name: M.replaceKeep}).click();
  await page.waitForTimeout(100);
  ok("«أبقِ نصي» لا يغيّر الاقتباس", (await lastAssistant(page).innerText()) === M.replaceKept && (await page.locator("#quote").inputValue()) === "لا تقربوا الصلاة" && reviews.length === 1);
  await panel(page).getByRole("button", {name: M.placeQuote}).click();
  await page.waitForTimeout(100);
  await page.locator(".assistant-msg").last().getByRole("button", {name: M.replaceConfirm}).click();
  await page.waitForTimeout(200);
  ok("بعد الموافقة فقط: يوضع النص دون مراجعة", (await page.locator("#quote").inputValue()) === "إن مع العسر يسرا" && reviews.length === 1 && await page.evaluate(() => document.activeElement?.id === "quote"));
  // الكتابة أثناء انتظار الإملاء تُعامل سؤالًا، لا اقتباسًا.
  await openPanel(page);
  await ask(page, "أريد إملاء الاقتباس بصوتي");
  await ask(page, "هل الخدمة مجانية ؟");
  ok("الكتابة أثناء الإملاء سؤال عادي", (await lastAssistant(page).innerText()) === I.free.answer && !(await panel(page).locator("#assistant-draft").count()));
  // إخفاء الصفحة أثناء الاستماع يوقف الميكروفون
  await panel(page).getByRole("button", {name: M.talk}).click();
  await page.waitForTimeout(50);
  const abortsBefore = (await a(page)).events.filter(e => e === "abort").length;
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pagehide")));
  await page.waitForTimeout(100);
  ok("pagehide يوقف الاستماع", (await a(page)).events.filter(e => e === "abort").length > abortsBefore && !(await panel(page).locator(".assistant-mic.is-listening").count()));
  await page.keyboard.press("Escape");
  // الإغلاق أثناء الاستماع
  await openPanel(page);
  await panel(page).getByRole("button", {name: M.talk}).click();
  await page.waitForTimeout(50);
  await panel(page).getByRole("button", {name: M.close}).click();
  await page.waitForTimeout(100);
  s = await a(page);
  ok("الإغلاق أثناء الاستماع يوقف الميكروفون", s.events.at(-1) === "abort" || s.events.includes("abort"));
  s = await a(page);
  ok("لا يُنطق إلا نص معدّ (لا اقتباس ولا ما سمعه)", s.speaks.every(t => prepared.has(t)), s.speaks.filter(t => !prepared.has(t)).join(" | "));
  ok("لا أخطاء JavaScript (٣)", errors.length === 0, errors.join(" | "));
  await ctx.close();
}
for (const [mode, name, msg] of [["denied", "رفض إذن الميكروفون", M.micDenied], ["network", "ضعف الاتصال بخدمة التعرف", M.network]]) {
  const {ctx, page, errors} = await open("desktop", mode);
  await openPanel(page);
  await panel(page).getByRole("button", {name: M.talk}).click();
  await page.waitForTimeout(250);
  const s = await a(page);
  ok(`${name}: رسالة واضحة دون إعادة تشغيل`, (await lastAssistant(page).innerText()) === msg && s.recs === 1);
  if (mode === "denied") ok("بعد الرفض يتعطل زر الصوت وتبقى الكتابة", await panel(page).getByRole("button", {name: M.talk}).isDisabled() && await page.locator("#assistant-input").isEnabled());
  await ask(page, "هل الخدمة مجانية ؟");
  ok(`${name}: الكتابة تعمل`, (await lastAssistant(page).innerText()) === I.free.answer);
  ok(`لا أخطاء JavaScript (${name})`, errors.length === 0, errors.join(" | "));
  await ctx.close();
}
{
  const {ctx, page, errors} = await open("desktop", "none");
  await openPanel(page);
  ok("متصفح بلا تعرف على الكلام: زر الصوت معطل مع توضيح", await panel(page).getByRole("button", {name: M.talk}).isDisabled() && (await panel(page).innerText()).includes(M.voiceUnsupported));
  await ask(page, "كيف أتواصل مع الدعم ؟");
  ok("بلا تعرف: الكتابة تعمل", (await lastAssistant(page).innerText()) === I.support.answer);
  ok("لا أخطاء JavaScript (بلا تعرف)", errors.length === 0, errors.join(" | "));
  await ctx.close();
}
{
  const {ctx, page, errors} = await open("desktop", "novoice");
  await openPanel(page);
  await page.waitForTimeout(250);
  const s = await a(page);
  ok("لا صوت عربي: لا نطق بصوت غير عربي، والردود مكتوبة", s.speaks.length === 0 && (await panel(page).innerText()).includes(M.noArabicVoice) && await panel(page).getByRole("button", {name: M.speechToggle}).isDisabled());
  ok("لا أخطاء JavaScript (لا صوت عربي)", errors.length === 0, errors.join(" | "));
  await ctx.close();
}
// ٤. العروض والهاتف والصور
for (const vp of ["desktop", "mobile", "small"]) {
  // حرر عمليات المتصفح بين المقاسات لتقليل الذاكرة على جهاز الاختبار.
  await browser.close(); browser = await launchBrowser();
  const {ctx, page, errors} = await open(vp);
  ok(`${vp}: لا تمرير أفقي واللوحة مغلقة`, (await overflow(page)) <= 0);
  await page.screenshot({path: `${out}/${vp}-1-الرئيسية-والزر.png`});
  await openPanel(page);
  await page.waitForTimeout(500);
  ok(`${vp}: لا تمرير أفقي واللوحة مفتوحة`, (await overflow(page)) <= 0);
  const box = await panel(page).boundingBox(); const vw = page.viewportSize();
  ok(`${vp}: اللوحة داخل الشاشة`, box.x >= 0 && box.x + box.width <= vw.width + 0.5 && box.y >= 0 && box.y + box.height <= vw.height + 0.5, JSON.stringify(box));
  const small = await panel(page).evaluate(el => [...el.querySelectorAll("button,input")].filter(b => b.offsetParent).map(b => b.getBoundingClientRect()).filter(r => r.height < 40).length);
  ok(`${vp}: أهداف النقر لا تقل عن ٤٠ بكسل`, small === 0, String(small));
  await page.screenshot({path: `${out}/${vp}-2-اللوحة.png`});
  await ask(page, "لدي صورة");
  await page.waitForTimeout(300);
  await page.screenshot({path: `${out}/${vp}-3-الصورة.png`});
  await page.keyboard.press("Escape");
  if (vp !== "desktop") {
    await page.locator("#quote").focus(); await page.waitForTimeout(100);
    ok(`${vp}: الزر يختفي أثناء الكتابة فلا يغطي المربع أو لوحة المفاتيح`, !(await launcher(page).isVisible()));
    await page.locator("#quote").blur();
  }
  const unnamed = await page.evaluate(() => [...document.querySelectorAll("button,a")].filter(e => e.offsetParent && !(e.getAttribute("aria-label") || e.textContent.trim())).length);
  ok(`${vp}: كل زر ظاهر له اسم`, unnamed === 0, String(unnamed));
  ok(`${vp}: لا أخطاء JavaScript`, errors.length === 0, errors.join(" | "));
  await ctx.close();
}
{
  const {ctx, page} = await open("mobile", "normal", "/sources");
  await openPanel(page); await page.waitForTimeout(300);
  await page.screenshot({path: `${out}/mobile-4-المصادر.png`});
  await ctx.close();
  const reduced = await browser.newContext({viewport: {width: 1366, height: 900}, reducedMotion: "reduce"});
  await reduced.addInitScript(mockSpeech, "normal");
  const p = await reduced.newPage(); await p.goto(base + "/", {waitUntil: "networkidle"}); await openPanel(p);
  ok("تقليل الحركة: لا انتقالات في عناصر المساعد", await p.evaluate(() => getComputedStyle(document.querySelector(".assistant-icon")).transitionDuration === "0s"));
  await reduced.close();
}
await browser.close();
const failed = results.filter(r => !r.pass).length;
writeFileSync(`${out}/نتائج-فحص-المساعد.json`, JSON.stringify({base, mock: "SpeechRecognition وspeechSynthesis محاكاة داخل الصفحة", failed, results}, null, 2));
console.log(`summary ${failed} failed of ${results.length}`);
process.exit(failed ? 1 : 0);
