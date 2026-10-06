import {test} from "node:test";
import assert from "node:assert/strict";
import content from "../src/content/assistant-responses.json";
import {ALLOWED_PATHS, intent, intents, matchRequest, messages, normalize, starters} from "../src/lib/assistant/intents";
import {existsSync, readFileSync, statSync} from "node:fs";
import {listenOnce, playClip, recognitionError, recognitionLang, type RecognitionLike} from "../src/lib/assistant/speech";
import {AUDIO_BASE, audioEntries, clipFor, displayTextFor} from "../src/lib/assistant/audio";

const id = (q: string) => {const m = matchRequest(q); return m.kind === "intent" ? m.intent.id : m.kind;};

test("the ten starter questions map to their own prepared answers", () => {
  assert.deepEqual(starters.map(s => s.question), ["ما سِياق ؟", "كيف أراجع اقتباسًا ؟", "كيف أستخدم صورة ؟", "ما مصادر التفسير ؟", "لماذا لا يظهر تفسير لبعض الآيات ؟", "هل نتائج التشابه مؤكدة ؟", "هل الخدمة مجانية ؟", "هل الصور تُرفع ؟", "كيف أجد السياق والمصدر ؟", "كيف أتواصل مع الدعم ؟"]);
  for (const s of starters) assert.equal(id(s.question), s.id, s.question);
  for (const i of intents) assert.equal(id(i.question), i.id, `question of ${i.id}`);
});

test("close wordings, spoken requests and actions are recognised", () => {
  const cases: [string, string][] = [
    ["ما هو سياق", "what_is"], ["أريد مراجعة اقتباس", "start_review"], ["عايز اراجع اقتباس", "start_review"], ["ابغى اراجع آية", "start_review"],
    ["لدي صورة", "image_how"], ["عندي صورة فيها آية", "image_how"], ["من أين التفسير", "tafsir_sources"], ["التفسير غير موجود لهذه الآية", "missing_tafsir"],
    ["هل النتيجة مؤكدة", "similarity"], ["بكام الخدمة", "free"], ["هل تحفظون الصور", "image_upload"], ["أين السياق", "context_source"],
    ["أريد المصادر", "open_sources"], ["افتح صفحة كيف يعمل", "open_methodology"], ["افتح صفحة الدعم", "open_support"], ["الخصوصية", "open_privacy"],
    ["افتح السياق", "open_context"], ["افتح التفسير", "open_tafsir"], ["أريد إملاء الاقتباس بصوتي", "dictate"], ["هل يحفظ صوتي", "voice_privacy"],
    ["السلام عليكم", "greeting"], ["شكرا", "thanks"], ["كيف أتواصل معكم", "support"],
  ];
  for (const [q, want] of cases) assert.equal(id(q), want, q);
});

test("religious questions and unrelated requests get the scope notice, not an answer", () => {
  for (const q of ["ما حكم الغناء", "هل يجوز القصر في السفر", "اشرح لي معنى آية الكرسي", "ما تفسير آية الكرسي", "اقرأ لي سورة الفاتحة", "أعطني فتوى", "ما الطقس اليوم"]) assert.equal(id(q), "out_of_scope", q);
});

test("unclear input asks for clarification, and a spoken quote is offered for the quote box only after confirmation", () => {
  assert.deepEqual(matchRequest("طيب"), {kind: "unclear", offerQuote: false});
  assert.deepEqual(matchRequest(""), {kind: "unclear", offerQuote: false});
  assert.deepEqual(matchRequest("إن مع العسر يسرا"), {kind: "unclear", offerQuote: true});
  const m = matchRequest("صورة السياق");
  assert.equal(m.kind, "clarify");
  if (m.kind === "clarify") assert.equal(m.options.length, 2);
});

test("prepared answers follow the project rules and never contain verses or other contacts", () => {
  assert.equal(messages.welcome, "مرحبًا بك في سِياق. كيف يمكنني مساعدتك ؟");
  assert.equal(messages.title, "مساعد سِياق — تجريبي");
  assert.equal(messages.notice, "مساعد سِياق — نسخة تجريبية للمساعدة في استخدام الموقع. يجيب من إرشادات معدّة مسبقًا، وقد تحتاج إلى تصحيح ما سمعه.");
  const all = [...Object.values(content.messages), ...content.intents.flatMap(i => [i.question, i.answer, (i as {spoken?: string}).spoken ?? ""])];
  for (const text of all) {
    assert.ok(!/[^\s]؟|[^\s]!/.test(text), `مسافة قبل علامة الاستفهام أو التعجب: ${text}`);
    assert.ok(!/[﴿﴾]/.test(text), `لا آيات في الردود: ${text}`);
    assert.ok(!/gmail|vercel\.app|@(?!mysiyaq\.com)/i.test(text), `بريد أو رابط غير معتمد: ${text}`);
  }
  assert.ok(intent("support").answer.includes("contact@mysiyaq.com"));
  assert.ok(!intent("support").spoken!.includes("@"), "البريد لا يُنطق حرفًا حرفًا");
  for (const i of intents) for (const a of i.actions) if (a.type === "page") assert.ok((ALLOWED_PATHS as readonly string[]).includes(a.path));
  assert.ok(!intent("what_is").answer.includes("خمس"), "المراجعة تشمل القرآن كاملًا");
  assert.match(intent("what_is").answer, /القرآن كاملًا/);
});

test("normalisation ignores diacritics and spelling variants", () => {
  assert.equal(normalize("سِيَاقٌ ؟ أإآ ى ة"), "سياق ااا ي ه");
});

test("speech helpers: errors and recognition language", () => {
  assert.equal(recognitionError("not-allowed"), "denied");
  assert.equal(recognitionError("service-not-allowed"), "denied");
  assert.equal(recognitionError("no-speech"), "no-speech");
  assert.equal(recognitionError("audio-capture"), "no-mic");
  assert.equal(recognitionError("network"), "network");
  assert.equal(recognitionError("language-not-supported"), "language");
  assert.equal(recognitionError("something-new"), "failed");
  assert.equal(recognitionLang(["ar-EG", "en-US"]), "ar-EG");
  assert.equal(recognitionLang(["en-US"]), "ar-SA");
});

// محاكاة SpeechRecognition (mock): تختبر منطق الاستماع، وليست تجربة تعرف صوتي حقيقية.
function fakeRecognition(script: (r: RecognitionLike) => void) {
  return class implements RecognitionLike {
    lang = ""; continuous = true; interimResults = false; maxAlternatives = 3;
    onresult: RecognitionLike["onresult"] = null; onerror: RecognitionLike["onerror"] = null; onend: RecognitionLike["onend"] = null;
    started = 0;
    start() {this.started++; queueMicrotask(() => script(this));}
    stop() {queueMicrotask(() => this.onend?.());}
    abort() {queueMicrotask(() => {this.onerror?.({error: "aborted"}); this.onend?.();});}
  };
}
const result = (text: string, isFinal: boolean) => ({resultIndex: 0, results: [Object.assign([{transcript: text}], {isFinal})]});

test("listening once returns the final transcript and never restarts itself", async () => {
  let instance: RecognitionLike | null = null;
  const Ctor = fakeRecognition(r => {instance = r; r.onresult?.(result("كيف أستخدم", false)); r.onresult?.(result("كيف أستخدم صورة", true)); r.onend?.();});
  const heard: string[] = [];
  const l = listenOnce(t => heard.push(t), {Ctor, lang: "ar-SA"})!;
  assert.deepEqual(await l.result, {ok: true, text: "كيف أستخدم صورة"});
  assert.deepEqual(heard, ["كيف أستخدم", "كيف أستخدم صورة"]);
  assert.equal(instance!.lang, "ar-SA");
  assert.equal(instance!.continuous, false);
  assert.equal((instance as unknown as {started: number}).started, 1);
});

test("listening reports denial, silence, network failure and cancellation", async () => {
  const fail = (code: string) => fakeRecognition(r => {r.onerror?.({error: code}); r.onend?.();});
  assert.deepEqual(await listenOnce(() => {}, {Ctor: fail("not-allowed")})!.result, {ok: false, error: "denied"});
  assert.deepEqual(await listenOnce(() => {}, {Ctor: fail("no-speech")})!.result, {ok: false, error: "no-speech"});
  assert.deepEqual(await listenOnce(() => {}, {Ctor: fail("network")})!.result, {ok: false, error: "network"});
  const silent = fakeRecognition(() => {});
  const l = listenOnce(() => {}, {Ctor: silent})!;
  l.abort();
  assert.deepEqual(await l.result, {ok: false, error: "aborted"});
  const timed = listenOnce(() => {}, {Ctor: silent, timeoutMs: 20})!;
  assert.deepEqual(await timed.result, {ok: false, error: "no-speech"});
  assert.equal(listenOnce(() => {}, {Ctor: null}), null);
});

test("negation never triggers an action, and compound requests are offered as choices", () => {
  for (const q of ["لا أريد فتح التفسير", "لا تفتح المصادر", "مش عايز اراجع اقتباس", "بلاش الصورة", "إلغاء", "لا أريد مراجعة اقتباس الآن"]) assert.equal(matchRequest(q).kind, "negated", q);
  // «لا» داخل سؤال أو اقتباس ليست نفيًا للطلب.
  assert.equal(id("لماذا لا يظهر تفسير لبعض الآيات ؟"), "missing_tafsir");
  assert.equal(matchRequest("لا تقربوا الصلاة").kind, "unclear");
  const compound = matchRequest("أريد مراجعة اقتباس ولدي صورة");
  assert.ok(compound.kind === "clarify" && compound.reason === "compound");
  if (compound.kind === "clarify") assert.deepEqual(compound.options.map(o => o.id).sort(), ["image_how", "start_review"]);
  const pages = matchRequest("افتح المصادر وافتح الدعم");
  assert.ok(pages.kind === "clarify" && pages.reason === "compound" && pages.options.length === 2);
  // التحية مع طلب واحد ليست طلبًا مركبًا، والمجموعة الواحدة لا تحتاج اختيارًا.
  assert.equal(id("السلام عليكم أريد المصادر"), "open_sources");
  assert.equal(id("أريد المصادر"), "open_sources");
  // سؤالان معلوماتيان بالوزن نفسه: اختيار بينهما.
  const tie = matchRequest("ما سياق وهل الخدمة مجانية");
  assert.ok(tie.kind === "clarify" && tie.reason === "tie");
});

test("every intent belongs to a family and negation phrases do not collide with the starter questions", () => {
  for (const i of intents) assert.ok(i.family, i.id);
  for (const s of starters) assert.notEqual(matchRequest(s.question).kind, "negated", s.question);
});

// كل رد قد يُنطق في اللوحة له تسجيل مستضاف مع الموقع، والنص المنطوق مشكول ولا يقول «صورة» (حتى لا تُسمع «سورة»).
const SPOKEN_MESSAGES = ["welcome", "imageShown", "actionFailed", "busy", "pageAlready", "pageOpened", "needResult", "dictationEmpty", "replaceAsk", "dictationReview", "compound", "clarify", "negated", "outOfScope", "unclear", "voiceUnsupported", "micDenied", "noSpeech", "noMic", "network", "languageUnsupported", "recognitionFailed"];
// هذه الإجابات تُغلق اللوحة أو تُعلن بإشعار، فلا تُنطق.
const SILENT_INTENTS = new Set(["start_review", "open_context", "open_tafsir"]);
test("every spoken reply has a prepared, hosted recording", () => {
  for (const k of SPOKEN_MESSAGES) assert.ok(clipFor((messages as Record<string, string>)[k]), `M.${k}`);
  for (const i of intents) if (!SILENT_INTENTS.has(i.id)) assert.ok(clipFor(i.spoken ?? i.answer), `I.${i.id}`);
  assert.equal(Object.keys(audioEntries).length, SPOKEN_MESSAGES.length + intents.length - SILENT_INTENTS.size);
  for (const [key, e] of Object.entries(audioEntries)) {
    assert.ok(displayTextFor(key), key);
    const file = `public${AUDIO_BASE}${e.file}`;
    assert.ok(existsSync(file), file);
    const size = statSync(file).size;
    assert.ok(size > 8000 && size < 250000, `${file}: ${size}`);
    assert.equal(readFileSync(file).subarray(0, 3).toString("latin1"), "ID3", `${file} is MP3`);
  }
  assert.equal(clipFor("نص كتبه الزائر"), null);
});
test("spoken texts are fully vocalised Fusha, say «لقطة» not «صورة», and keep the punctuation rules", () => {
  const harakat = /[\u064B-\u0652]/g;
  for (const [key, e] of Object.entries(audioEntries)) {
    const letters = (e.spoken.match(/[\u0621-\u064A]/g) ?? []).length;
    const marks = (e.spoken.match(harakat) ?? []).length;
    assert.ok(marks / letters > 0.6, `${key}: ${marks}/${letters}`);
    assert.doesNotMatch(e.spoken, /صور/, key);
    assert.doesNotMatch(e.spoken, /\S[؟!]/, key);
    assert.doesNotMatch(e.spoken, /[﴿﴾]/, key);
  }
});
test("a clip player resolves on end, reports failure, and cancels without leaking", async () => {
  const make = (mode: "end" | "error" | "reject") => () => {
    const a = {src: "", preload: "", currentTime: 0, paused: true, onended: null as (() => void) | null, onerror: null as (() => void) | null,
      play() {a.paused = false; if (mode === "reject") return Promise.reject(new Error("blocked")); setTimeout(() => mode === "end" ? a.onended?.() : a.onerror?.(), 5); return Promise.resolve();},
      pause() {a.paused = true;}};
    return a;
  };
  assert.deepEqual(await playClip("/x.mp3", make("end")).done, {ok: true});
  assert.deepEqual(await playClip("/x.mp3", make("error")).done, {ok: false});
  assert.deepEqual(await playClip("/x.mp3", make("reject")).done, {ok: false});
  const p = playClip("/x.mp3", make("end")); p.cancel();
  assert.deepEqual(await p.done, {ok: true});
});

test("recognition network errors finish immediately without acting on partial words", async () => {
  const Ctor = fakeRecognition(r => {r.onresult?.(result("افتح", false)); r.onerror?.({error: "network"});});
  assert.deepEqual(await listenOnce(() => {}, {Ctor, timeoutMs: 100})!.result, {ok: false, error: "network"});
});

test("buffered clips wait for all bytes and cancellation never plays a late download", async () => {
  const saved = globalThis.fetch;
  let ready!: (blob: Blob) => void, played = 0;
  globalThis.fetch = (async () => ({ok: true, blob: () => new Promise<Blob>(resolve => {ready = resolve;})})) as unknown as typeof fetch;
  const audio = {src: "", preload: "", currentTime: 0, onended: null as (() => void) | null, onerror: null as (() => void) | null,
    play() {played++; return Promise.resolve();}, pause() {}};
  try {
    const clip = playClip("/assistant-audio/buffer-regression.mp3", () => audio, {buffer: true});
    await Promise.resolve(); assert.equal(played, 0);
    ready(new Blob(["fixture bytes"], {type: "audio/mpeg"}));
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(played, 1); assert.ok(audio.src.startsWith("blob:")); audio.onended?.();
    assert.deepEqual(await clip.done, {ok: true});
    const cancelled = playClip("/assistant-audio/cancel-regression.mp3", () => audio, {buffer: true});
    await Promise.resolve(); cancelled.cancel(); ready(new Blob(["fixture bytes"]));
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(played, 1); assert.deepEqual(await cancelled.done, {ok: true});
  } finally {globalThis.fetch = saved;}
});
