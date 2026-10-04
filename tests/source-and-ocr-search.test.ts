// تعديلات ٣ أكتوبر: البحث بعد قراءة الصور، والروابط المباشرة، والمصادر ونسخها.
import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {createMatcher} from "../src/lib/matcher";
import {prepareSearch} from "../src/lib/normalize";
import {ABOUT_SOURCES, AYAH_COUNTS, DORAR_NOTE, VERIFIED_TAFSIR_BOOKS, TAFSIR_SURAH_SLUGS, dorarPassage, tafsirAyahURL, tafsirPageURL, verseURL} from "../src/lib/links";
import type {Verse, Tafsir} from "../src/lib/types";
const quran = JSON.parse(readFileSync("data/quran.json", "utf8")) as Verse[];
const tafsir = JSON.parse(readFileSync("data/tafsir.json", "utf8")) as Record<string, Tafsir[]>;
const review = createMatcher(quran, tafsir, "test");
const ocrSample = readFileSync("tests/fixtures/ocr-4-43.txt", "utf8");
const confirmed = (r: ReturnType<typeof review>) => r.status === "matched" && r.selected !== null && r.selected.kind !== "possible";

test("عينة الصورة: تفريغها الأصلي محفوظ، والبحث يصل إلى النساء ٤٣ موضعًا محتملًا لا مؤكدًا", () => {
  const r = review(ocrSample);
  assert.equal(r.quote, ocrSample, "التفريغ الأصلي يعود كما هو للمراجعة");
  assert.equal(r.status, "possible");
  assert.equal(r.selected, null, "لا اختيار تلقائي");
  assert.equal(r.search.method, "segments");
  assert.equal(r.candidates[0].id, "4:43");
  for (const token of ["Ne/a", "Mae/", "Aig0/A", "«قال تعالى»"]) assert.ok(r.search.ignored.includes(token), token);
  assert.ok(!/[A-Za-z0-9]/.test(r.search.query));
  const s = review(ocrSample, "4:43");
  assert.equal(s.selected?.kind, "possible", "يبقى احتمالًا بعد الاختيار");
  assert.deepEqual(s.differences.filter(d => d.type !== "same").map(d => `${d.type}:${d.text}`), ["input:الغردور"], "الكلمة الدخيلة تظهر فرقًا ولا تُصحَّح بصمت");
  assert.equal(s.selected!.verses[0].text, quran.find(v => v.id === "4:43")!.text, "النص القرآني المعروض من المصدر كما هو");
});

test("النص النظيف المقابل من المصدر يطابق مطابقة كاملة مؤكدة", () => {
  const clean = quran.find(v => v.id === "4:43")!.text;
  const r = review(clean);
  assert.ok(confirmed(r)); assert.equal(r.selected?.id, "4:43"); assert.equal(r.selected?.kind, "full"); assert.equal(r.search.method, "exact"); assert.deepEqual(r.search.ignored, []);
});

test("رموز دخيلة حول اقتباس صحيح تُهمل في البحث وتُذكر", () => {
  const r = review("قال تعالى : {لا تقربوا الصلاة وأنتم سكارى} Ne/a");
  assert.equal(r.selected?.id, "4:43"); assert.equal(r.selected?.kind, "partial"); assert.equal(r.search.method, "exact");
  assert.deepEqual(r.search.ignored, ["«قال تعالى»", "Ne/a"]);
});

test("اقتباس متكرر مع رمز دخيل يبقى اختيارًا بلا تحديد تلقائي", () => {
  const r = review("الحمد لله رب العالمين Mae/");
  assert.equal(r.status, "choices"); assert.equal(r.selected, null); assert.ok(r.candidateCount > 1);
});

test("نص غير قرآني يحوي عبارة قرآنية شائعة لا يعطي نتيجة مؤكدة ولا مقاطع", () => {
  for (const text of ["قال المحاضر في درس الأمس إن الله غفور رحيم بعباده جميعا Ne/a", "اللهم بارك لنا في الوقت والعمل والصحة والأهل Aig0/A", "هذه رسالة تجريبية من قراءة صورة لا علاقة لها بالقرآن"]) {
    const r = review(text);
    assert.equal(r.status, "not_found", text); assert.equal(r.selected, null); assert.equal(r.tafsir.length, 0);
  }
});

test("«قال تعالى» تُحذف من البداية فقط، ولا تُحذف كلمات من وسط النص", () => {
  assert.deepEqual(prepareSearch("قال تعالى: إن مع العسر يسرا"), {query: "ان مع العسر يسرا", ignored: ["«قال تعالى»"]});
  assert.equal(prepareSearch("إن مع العسر يسرا قال تعالى").query, "ان مع العسر يسرا قال تعالي");
  assert.equal(prepareSearch("قال تعالى").query, "قال تعالي", "لا تُحذف إن لم يبقَ اقتباس");
});

test("لا نتيجة مؤكدة خاطئة: كل مرشح بالمقاطع موضع محتمل، وأول مرشح يغطي معظم الاقتباس", () => {
  const damaged = "يا ايها الذين امنوا كتب عليكم الصيام كما كتب Xq/7 على الذين من قبلكم لعلكم تتقون الغردور";
  const r = review(damaged);
  assert.equal(r.status, "possible"); assert.equal(r.candidates[0].id, "2:183");
  assert.ok(r.candidates.every(c => c.kind === "possible"));
});

test("روابط النص المباشرة: صفحة الآية نفسها في مصحف حفص، وتُرفض الآية غير الموجودة", () => {
  assert.equal(verseURL(1, 1), "https://quranpedia.net/surah/1/1/1");
  assert.equal(verseURL(2, 255), "https://quranpedia.net/surah/1/2/255");
  assert.equal(verseURL(4, 43), "https://quranpedia.net/surah/1/4/43");
  assert.equal(verseURL(114, 6), "https://quranpedia.net/surah/1/114/6");
  for (const [s, a] of [[1, 8], [0, 1], [115, 1], [2, 287], [4, 0]]) assert.equal(verseURL(s, a), null, `${s}:${a}`);
  assert.equal(AYAH_COUNTS.reduce((a, b) => a + b), 6236);
  const counts = new Map<number, number>(); for (const v of quran) counts.set(v.surah, (counts.get(v.surah) ?? 0) + 1);
  assert.deepEqual([...counts.values()], AYAH_COUNTS, "عدد الآيات يطابق البيانات المعتمدة");
  for (const v of quran) assert.ok(verseURL(v.surah, v.ayah), v.id);
});

test("روابط تفسير الآية تختار الكتاب والآية وتحافظ على رقمها في جميع النتائج", () => {
  assert.equal(TAFSIR_SURAH_SLUGS.length, 114);
  assert.equal(new Set(TAFSIR_SURAH_SLUGS).size, 114);
  assert.equal(tafsirAyahURL(269, 14, 43), "https://quranpedia.net/tafsir/ibrahim/43?book=269");
  assert.equal(tafsirAyahURL(27758, 14, 43), "https://quranpedia.net/tafsir/ibrahim/43?book=27758");
  assert.equal(tafsirAyahURL(269, 14, 53), null);
  assert.equal(tafsirAyahURL(999, 14, 43), null);
  for (const [id, entries] of Object.entries(tafsir)) {
    const [surah, ayah] = id.split(":").map(Number);
    for (const entry of entries) {
      const url = new URL(tafsirAyahURL(entry.bookId, surah, ayah)!);
      assert.equal(url.pathname, `/tafsir/${TAFSIR_SURAH_SLUGS[surah - 1]}/${ayah}`);
      assert.equal(url.searchParams.get("book"), String(entry.bookId));
    }
  }
});

test("الدرر: إبراهيم٤٢ و٤٣ يفتحان المقطع المحدد مع التحقق من حدود المقاطع", () => {
  assert.deepEqual(dorarPassage(14, 42), {firstAyah: 42, lastAyah: 46, url: "https://dorar.net/tafseer/14/11"});
  assert.deepEqual(dorarPassage(14, 43), dorarPassage(14, 42));
  assert.equal(dorarPassage(14, 41)?.url, "https://dorar.net/tafseer/14/10");
  assert.equal(dorarPassage(14, 47)?.url, "https://dorar.net/tafseer/14/12");
  for (let ayah = 1; ayah <= 52; ayah++) {
    const passage = dorarPassage(14, ayah);
    assert.ok(passage && passage.firstAyah <= ayah && ayah <= passage.lastAyah);
  }
  assert.equal(dorarPassage(14, 53), null);
  assert.equal(dorarPassage(14, 0), null);
  assert.equal(dorarPassage(4, 43), null, "لا نخمن مقطع سورة لم تراجع روابطها");
});

test("روابط التفسير: صفحة الكتاب المطبوعة لكل نص محفوظ، وتخص الآية نفسها", () => {
  assert.equal(tafsirPageURL(269, "1", 276), "https://quranpedia.net/book/269/1/276");
  assert.equal(tafsirPageURL(27758, "1", 214), "https://quranpedia.net/book/27758/1/214");
  assert.equal(tafsirPageURL(3, "1", 10), null, "كتاب لم يُفحص نمطه");
  assert.equal(tafsirPageURL(269, "", 276), null); assert.equal(tafsirPageURL(269, "1", null), null);
  let entries = 0;
  for (const [id, list] of Object.entries(tafsir)) {
    const [s, a] = id.split(":");
    for (const e of list) {
      entries++;
      assert.ok(tafsirPageURL(e.bookId, e.part, e.page), `${id} ${e.bookId}`);
      assert.ok(e.url.includes(`/ayah/${s}/${a}/book/${e.bookId}`), `${id}: ${e.url}`);
    }
  }
  assert.equal(entries, 2868);
});

test("عدة سور وآيات: النص والسياق والتفسير لكل نتيجة تخص الآيات المحددة نفسها", () => {
  const cases: [string, string][] = [["لا تقربوا الصلاة", "4:43"], ["إن مع العسر يسرا", "94:6"], ["قل هو الله أحد", "112:1"], ["رب العالمين الرحمن الرحيم", "1:2+1:3"], ["من الجنة والناس", "114:6"]];
  for (const [q, id] of cases) {
    const r = review(q, id);
    const ids = r.selected!.verses.map(v => v.id);
    assert.equal(r.selected!.id, id);
    assert.deepEqual(r.tafsir.map(g => g.verseId), ids, q);
    for (const g of r.tafsir) for (const e of g.entries) assert.deepEqual(e, tafsir[g.verseId].find(x => x.text === e.text), "نص التفسير منقول كما هو");
    assert.ok(r.context.every(v => v.surah === r.selected!.verses[0].surah));
  }
});

test("تبديل سريع بين مواضع نتيجة واحدة لا يخلط التفسير أو السياق", () => {
  const q = "الحمد لله رب العالمين";
  const choices = review(q).candidates.map(c => c.id).slice(0, 4);
  const results = choices.map(id => review(q, id));
  results.forEach((r, i) => {
    assert.equal(r.selected?.id, choices[i]);
    assert.deepEqual(r.tafsir.map(g => g.verseId), r.selected!.verses.map(v => v.id));
    assert.ok(r.context.some(v => v.id === choices[i]));
  });
});

test("المصادر ونسخها الحقيقية من سجل الاستيراد", async () => {
  const {reviewQuote} = await import("../src/lib/data");
  const r = reviewQuote("لا تقربوا الصلاة");
  assert.deepEqual(r.sources.quran, {name: "الموسوعة القرآنية", version: "2026-10-01"});
  assert.deepEqual(r.sources.tafsir.map(b => [b.bookId, b.version]), [[269, "2026-08-10"], [27758, "2026-08-10"]]);
});

test("about sources list exactly what results use, with roles and correct general links", () => {
  const provenance = JSON.parse(readFileSync(join(process.cwd(), "data", "provenance.json"), "utf8")) as {books: {id: number; name: string}[]};
  const policy = JSON.parse(readFileSync(join(process.cwd(), "data", "source-policy.json"), "utf8")) as {tafsir_books: {bookId: number; name: string; authorDeathAH: number; metadataURL: string}[]};
  assert.equal(ABOUT_SOURCES[0].title, "الموسوعة القرآنية");
  assert.equal(ABOUT_SOURCES[0].url, "https://quranpedia.net/");
  const listed = ABOUT_SOURCES.filter(s => s.tafsirBookId != null);
  assert.deepEqual(new Set(listed.map(s => s.tafsirBookId)), VERIFIED_TAFSIR_BOOKS);
  assert.deepEqual(listed.map(s => s.tafsirBookId).sort(), provenance.books.map(b => b.id).sort());
  for (const s of listed) {
    const rule = policy.tafsir_books.find(b => b.bookId === s.tafsirBookId)!;
    assert.ok(rule && rule.authorDeathAH <= 300, `${s.title} يحقق شرط القرون الثلاثة`);
    assert.equal(s.url, rule.metadataURL);
    assert.equal(s.title, provenance.books.find(b => b.id === s.tafsirBookId)!.name);
  }
  for (const s of ABOUT_SOURCES) {
    assert.ok(s.role.length > 10);
    assert.match(s.url, /^https:\/\/quranpedia\.net\//);
    for (const banned of ["حديث", "الفقه", "dorar", "shamela", "الدرر"]) assert.ok(!(s.title + s.role + s.url).includes(banned), banned);
  }
  assert.match(DORAR_NOTE, /لم تُربط/);
});
