export type Verse = {id: string; surah: number; surahName: string; ayah: number; text: string};
export type Tafsir = {bookId: number; bookName: string; author: string; part: string; page: number | null; text: string; url: string};
export type MatchKind = "full" | "partial" | "spanning" | "possible";
export type Candidate = {id: string; kind: MatchKind; verses: Verse[]; note: string};
export type ReviewResult = {
  status: "matched" | "choices" | "possible" | "not_found";
  quote: string;
  candidates: Candidate[];
  candidateCount: number;
  selected: Candidate | null;
  context: Verse[];
  tafsir: {verseId: string; entries: Tafsir[]}[];
  differences: {text: string; type: "same" | "input" | "source"}[];
  sourceVersion: string;
  /** إضافة اختيارية: نسخة البحث وما أُهمل منها، وطريقة الوصول للمواضع. الاقتباس الأصلي في quote كما هو. */
  search: {query: string; ignored: string[]; method: "exact" | "segments" | "similar" | "none"};
  /** إضافة اختيارية: مصدر النص ونسخته، وكتب التفسير المحمّلة التي بُحث فيها ونسخ بياناتها. */
  sources: {quran: {name: string; version: string}; tafsir: {bookId: number; name: string; author: string; version: string}[]};
};
