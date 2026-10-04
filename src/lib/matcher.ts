import { editDistance, normalizeSearch, prepareSearch } from "./normalize";
import type { Candidate, ReviewResult, Tafsir, Verse } from "./types";
import { InputError } from "./api";

const LIMIT = 12;
const NOTE = "تُوحَّد علامات التشكيل وبعض صور الهمزة والرسم للبحث فقط؛ النص الأصلي معروض كما ورد في المصدر.";
type IndexedVerse = {verse: Verse; normalized: string; words: string[]};

export type MatcherSources = ReviewResult["sources"];
const SEGMENT_MIN_RUN = 3;
const SEGMENT_MIN_COVERAGE = 0.6;

export function createMatcher(verses: Verse[], tafsir: Record<string, Tafsir[]>, sourceVersion: string, sources?: MatcherSources) {
  const index: IndexedVerse[] = verses.map(verse => ({verse, normalized: normalizeSearch(verse.text), words: normalizeSearch(verse.text).split(" ")}));
  const positions = new Map(verses.map((verse, i) => [verse.id, i]));
  // فهرس مقاطع من ثلاث كلمات داخل كل آية: يحدد الآيات المرشحة للبحث بالمقاطع دون مسح القرآن كله.
  const shingles = new Map<string, number[]>();
  index.forEach((row, i) => {
    for (let k = 0; k + SEGMENT_MIN_RUN <= row.words.length; k++) {
      const key = row.words.slice(k, k + SEGMENT_MIN_RUN).join(" ");
      const list = shingles.get(key);
      if (!list) shingles.set(key, [i]); else if (list.at(-1) !== i) list.push(i);
    }
  });
  const resolvedSources: MatcherSources = sources ?? {quran: {name: "الموسوعة القرآنية", version: sourceVersion}, tafsir: []};
  function candidate(rows: IndexedVerse[], kind: Candidate["kind"]): Candidate {
    return {id: rows.map(r => r.verse.id).join("+"), kind, verses: rows.map(r => r.verse), note: kind === "possible" ? "هذا موضع محتمل بسبب تشابه الألفاظ؛ ليس إثباتًا للمطابقة. قارن الكلمات بالنص الأصلي." : kind === "partial" ? "الاقتباس جزء من الآية. لا يعني الاختصار وحده أن الاقتباس خاطئ؛ راجع بقية الآية وتفسيرها." : kind === "spanning" ? "يمتد الاقتباس عبر آيات متجاورة من السورة نفسها." : NOTE};
  }
  function exact(query: string): Candidate[] {
    const results: Candidate[] = [];
    const framed = " " + query + " ";
    for (let i = 0; i < index.length; i++) {
      const row = index[i];
      if ((" " + row.normalized + " ").includes(framed)) {
        results.push(candidate([row], row.normalized === query ? "full" : "partial"));
        continue;
      }
      // A result may span up to three adjacent verses, but must cross every boundary.
      for (let count = 2; count <= 3 && i + count <= index.length; count++) {
        const rows = index.slice(i, i + count);
        if (rows.some(r => r.verse.surah !== row.verse.surah)) break;
        const joined = rows.map(r => r.normalized).join(" ");
        const start = (" " + joined + " ").indexOf(framed);
        const firstEnd = row.normalized.length + 1;
        const lastStart = joined.length - rows[count - 1].normalized.length + 1;
        if (start >= 0 && start < firstEnd && start + framed.length - 1 > lastStart) results.push(candidate(rows, "spanning"));
      }
    }
    return results;
  }
  function possible(query: string): Candidate[] {
    const words = query.split(" ");
    if (words.length < 3 || words.length > 35 || query.length < 12) return [];
    const unique = new Set(words);
    const maxDistance = Math.min(4, Math.floor(query.length * .16));
    const scored: {candidate: Candidate; score: number}[] = [];
    for (const row of index) {
      const overlap = new Set(row.words.filter(w => unique.has(w))).size;
      if (overlap < Math.max(2, Math.ceil(unique.size * .55))) continue;
      let best = maxDistance + 1;
      for (const length of [words.length - 1, words.length, words.length + 1]) {
        for (let start = 0; length > 0 && start + length <= row.words.length; start++) {
          best = Math.min(best, editDistance(query, row.words.slice(start, start + length).join(" "), maxDistance));
        }
      }
      if (best <= maxDistance) scored.push({candidate: candidate([row], "possible"), score: best});
    }
    return scored.sort((a, b) => a.score - b.score).map(r => r.candidate);
  }

  /** تغطية الاقتباس بمقاطع متصلة (٣ كلمات فأكثر) داخل نص المرشح، دون أي تصحيح للكلمات. */
  function coverage(query: string[], window: string[]): {covered: number; longest: number} {
    const at = new Map<string, number[]>();
    window.forEach((w, p) => {const list = at.get(w); if (list) list.push(p); else at.set(w, [p]);});
    let covered = 0, longest = 0;
    for (let i = 0; i < query.length;) {
      let best = 0;
      for (const p of at.get(query[i]) ?? []) {
        let k = 0;
        while (i + k < query.length && p + k < window.length && query[i + k] === window[p + k]) k++;
        best = Math.max(best, k);
      }
      if (best >= SEGMENT_MIN_RUN) {covered += best; longest = Math.max(longest, best); i += best;} else i++;
    }
    return {covered, longest};
  }

  /**
   * حين تفشل المطابقة الكاملة: البحث بمقاطع عربية واضحة من الاقتباس (مثل نص مقروء من صورة فيه كلمة دخيلة).
   * النتائج «مواضع محتملة» يختار منها المستخدم؛ لا تُعد مطابقة مؤكدة أبدًا.
   */
  function segments(query: string): Candidate[] {
    const words = query.split(" ");
    if (words.length < 4) return [];
    const hits = new Map<number, number>();
    for (let k = 0; k + SEGMENT_MIN_RUN <= words.length; k++) {
      for (const i of shingles.get(words.slice(k, k + SEGMENT_MIN_RUN).join(" ")) ?? []) hits.set(i, (hits.get(i) ?? 0) + 1);
    }
    const seeds = [...hits.entries()].sort((a, b) => b[1] - a[1]).slice(0, 60).map(([i]) => i);
    const minRun = words.length <= 5 ? SEGMENT_MIN_RUN : SEGMENT_MIN_RUN + 1;
    const found = new Map<string, {candidate: Candidate; covered: number}>();
    for (const seed of seeds) {
      for (let start = Math.max(0, seed - 2); start <= seed; start++) {
        for (let count = 1; count <= 3 && start + count <= index.length; count++) {
          if (start + count <= seed) continue;
          const rows = index.slice(start, start + count);
          if (rows.some(r => r.verse.surah !== rows[0].verse.surah)) break;
          const {covered, longest} = coverage(words, rows.flatMap(r => r.words));
          if (longest < minRun || covered < Math.ceil(words.length * SEGMENT_MIN_COVERAGE)) continue;
          // كل آية في النافذة يجب أن تسهم بمقطع؛ وإلا فالنافذة الأصغر تكفي.
          if (count > 1 && rows.some(r => coverage(words, r.words).covered === 0)) continue;
          const c = candidate(rows, "possible");
          const prior = found.get(c.id);
          if (!prior || prior.covered < covered) found.set(c.id, {candidate: c, covered});
        }
      }
    }
    const ranked = [...found.values()].sort((a, b) => b.covered - a.covered || a.candidate.verses.length - b.candidate.verses.length);
    // نافذة أوسع لا تضيف تغطية على نافذة داخلها تُستبعد.
    return ranked.filter((row, i) => !ranked.some((other, j) => j !== i && other.covered >= row.covered && other.candidate.verses.length < row.candidate.verses.length && other.candidate.verses.every(v => row.candidate.verses.some(w => w.id === v.id)))).map(r => r.candidate);
  }

  function differences(query: string, selected: Candidate): ReviewResult["differences"] {
    if (selected.kind !== "possible") return [];
    const input = query.split(" ");
    const source = selected.verses.flatMap(v => normalizeSearch(v.text).split(" "));
    // Align the closest word window; avoid labelling the rest of a partial verse as an error.
    let reference = source; let score = Number.POSITIVE_INFINITY;
    for (const length of [input.length - 1, input.length, input.length + 1]) {
      for (let start = 0; length > 0 && start + length <= source.length; start++) {
        const segment = source.slice(start, start + length);
        const distance = editDistance(input.join(" "), segment.join(" "), 1000);
        if (distance < score) {score = distance; reference = segment;}
      }
    }
    const dp = Array.from({length: input.length + 1}, () => Array(reference.length + 1).fill(0) as number[]);
    for (let i = input.length - 1; i >= 0; i--) for (let j = reference.length - 1; j >= 0; j--) dp[i][j] = input[i] === reference[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
    const result: ReviewResult["differences"] = []; let i = 0; let j = 0;
    while (i < input.length || j < reference.length) {
      if (i < input.length && j < reference.length && input[i] === reference[j]) {result.push({text: input[i++], type: "same"}); j++;}
      else if (i < input.length && (j === reference.length || dp[i + 1][j] >= dp[i][j + 1])) result.push({text: input[i++], type: "input"});
      else result.push({text: reference[j++], type: "source"});
    }
    return result;
  }

  return function review(quote: string, selection?: string): ReviewResult {
    if (typeof quote !== "string" || quote.length > 1000) throw new InputError("ضع اقتباسًا لا يتجاوز ١٠٠٠ حرف.");
    const {query: normalized, ignored} = prepareSearch(quote);
    if (normalized.length < 5 || normalized.split(" ").length < 2) throw new InputError("اكتب كلمتين على الأقل حتى نتمكن من تحديد موضع الاقتباس.");
    let candidates = exact(normalized);
    const hasExact = candidates.length > 0;
    let method: ReviewResult["search"]["method"] = hasExact ? "exact" : "none";
    if (!hasExact) {
      candidates = segments(normalized);
      if (candidates.length) method = "segments";
      else {candidates = possible(normalized); if (candidates.length) method = "similar";}
    }
    const requested = selection ? candidates.find(c => c.id === selection) : null;
    if (selection && !requested) throw new InputError("اختر موضعًا من نتائج الاقتباس الحالي.");
    const selected = requested ?? (hasExact && candidates.length === 1 ? candidates[0] : null);
    const context: Verse[] = [];
    if (selected) {
      const start = positions.get(selected.verses[0].id)!;
      const end = positions.get(selected.verses.at(-1)!.id)!;
      for (let i = Math.max(0, start - 1); i <= Math.min(index.length - 1, end + 1); i++) if (verses[i].surah === selected.verses[0].surah) context.push(verses[i]);
    }
    return {status: selected ? "matched" : candidates.length ? hasExact ? "choices" : "possible" : "not_found", quote, candidates: candidates.slice(0, LIMIT), candidateCount: candidates.length, selected, context, tafsir: selected ? selected.verses.map(v => ({verseId: v.id, entries: tafsir[v.id] ?? []})) : [], differences: selected ? differences(normalized, selected) : [], sourceVersion, search: {query: normalized, ignored, method}, sources: resolvedSources};
  };
}
