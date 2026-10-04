// This index-only normalization MUST NEVER be applied to displayed Quran text.
export function normalizeSearch(text: string): string {
  return text.normalize("NFKC")
    .replace(/[\u0640\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]/g, "")
    .replace(/\p{M}/gu, "")
    .replace(/[أإآٱ]/g, "ا").replace(/ى/g, "ي")
    .replace(/[^\p{L}\s]/gu, " ")
    .replace(/\s+/g, " ").trim()
    .split(" ").map(w => ({"الصلوة": "الصلاة", "صلوة": "صلاة", "الزكوة": "الزكاة", "زكوة": "زكاة", "الحيوة": "الحياة", "حيوة": "حياة"}[w] ?? w)).join(" ");
}

export function editDistance(a: string, b: string, limit: number): number {
  if (Math.abs(a.length - b.length) > limit) return limit + 1;
  let previous = Array.from({length: b.length + 1}, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const row = [i];
    for (let j = 1; j <= b.length; j++) row[j] = Math.min(row[j - 1] + 1, previous[j] + 1, previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    if (Math.min(...row) > limit) return limit + 1;
    previous = row;
  }
  return previous[b.length];
}

// عبارات تمهيد شائعة قبل الاقتباس (بعد التطبيع)؛ ليست من النص المقتبس. تُحذف من بداية نسخة البحث فقط.
const INTRO_PHRASES = ["قال الله سبحانه وتعالي", "قال الله عز وجل", "يقول الله تعالي", "قال الله تعالي", "قوله تعالي", "قال سبحانه", "قال تعالي"];

export type PreparedSearch = {query: string; ignored: string[]};

/**
 * نسخة البحث من الاقتباس — للفهرسة فقط، والاقتباس الأصلي يُعاد كما هو للمراجعة.
 * تُهمل: رموز دخيلة بحروف لاتينية أو أرقام (مثل Ne/a وMae/ وAig0/A من قراءة الصور)، وعبارة تمهيد
 * مثل «قال تعالى» في البداية فقط. التشكيل والأقواس وعلامات الوقف والمسافات يعالجها normalizeSearch.
 * لا تُصحَّح أي كلمة عربية؛ ما يبقى من الكلمات العربية يُبحث عنه كما هو.
 */
export function prepareSearch(text: string): PreparedSearch {
  const ignored: string[] = [];
  const kept: string[] = [];
  for (const token of text.normalize("NFKC").split(/\s+/)) {
    if (!token) continue;
    const foreign = /[A-Za-z0-9\u00C0-\u024F]/.test(token);
    const arabic = /\p{Script=Arabic}/u.test(token) && /\p{L}/u.test(token.replace(/[^\p{Script=Arabic}]/gu, ""));
    if (foreign && !arabic) { ignored.push(token); continue; }
    if (foreign) { ignored.push(token.replace(/[^A-Za-z0-9\u00C0-\u024F/]/g, "")); kept.push(token.replace(/[A-Za-z0-9\u00C0-\u024F]/g, " ")); continue; }
    kept.push(token);
  }
  let query = normalizeSearch(kept.join(" "));
  for (const phrase of INTRO_PHRASES) {
    if (query.startsWith(phrase + " ") && query.slice(phrase.length + 1).split(" ").length >= 2) {
      ignored.unshift("«" + phrase.replace(/ي$/, "ى") + "»");
      query = query.slice(phrase.length + 1);
      break;
    }
  }
  return {query, ignored: ignored.filter(Boolean)};
}
