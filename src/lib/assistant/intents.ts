// مطابقة طلب الزائر بإجابة معدّة مسبقًا. هذه قواعد كلمات مفتاحية بسيطة وشفافة، وليست نموذجًا مدرّبًا:
// كل إجابة وكل إجراء مكتوبان في src/content/assistant-responses.json، والمساعد لا يولّد نصًا.
import content from "@/content/assistant-responses.json";

export type AssistantAction =
  | {type: "focusQuote"; label: string}
  | {type: "pickImage"; label: string}
  | {type: "page"; path: AllowedPath; label: string}
  | {type: "openTab"; tab: AssistantTab; label: string};
export type AssistantTab = "context" | "tafsir";
// الصفحات الوحيدة التي يفتحها المساعد. لا يُنفَّذ رابط أو مسار من كلام المستخدم.
export const ALLOWED_PATHS = ["/", "/sources", "/methodology", "/support", "/privacy"] as const;
export type AllowedPath = (typeof ALLOWED_PATHS)[number];
// ما ينفذه المساعد فور مطابقة الطلب. القيم محصورة في هذه القائمة.
export type RunAction = {type: "focusQuote"} | {type: "showImage"} | {type: "dictate"} | {type: "page"; path: AllowedPath} | {type: "openTab"; tab: AssistantTab};

export type Intent = {id: string; family: string; question: string; answer: string; spoken?: string; keywords: string[]; actions: AssistantAction[]; run?: RunAction};
export type Messages = typeof content.messages;
export const messages: Messages = content.messages;

function parseRun(run: string | undefined, id: string): RunAction | undefined {
  if (!run) return undefined;
  if (run === "focusQuote" || run === "showImage" || run === "dictate") return {type: run};
  const [kind, value] = run.split(":");
  if (kind === "page" && (ALLOWED_PATHS as readonly string[]).includes(value)) return {type: "page", path: value as AllowedPath};
  if (kind === "openTab" && (value === "context" || value === "tafsir")) return {type: "openTab", tab: value};
  throw new Error(`إجراء غير مسموح في الإجابة ${id}: ${run}`);
}
function parseAction(raw: Record<string, string>, id: string): AssistantAction {
  const label = raw.label;
  if (!label) throw new Error(`إجراء بلا عنوان في الإجابة ${id}`);
  if (raw.type === "focusQuote" || raw.type === "pickImage") return {type: raw.type, label};
  if (raw.type === "page" && (ALLOWED_PATHS as readonly string[]).includes(raw.path)) return {type: "page", path: raw.path as AllowedPath, label};
  if (raw.type === "openTab" && (raw.tab === "context" || raw.tab === "tafsir")) return {type: "openTab", tab: raw.tab, label};
  throw new Error(`إجراء غير مسموح في الإجابة ${id}: ${JSON.stringify(raw)}`);
}

export const intents: Intent[] = content.intents.map(raw => {
  const r = raw as {id: string; family: string; question: string; answer: string; spoken?: string; keywords: string[]; actions?: Record<string, string>[]; run?: string};
  if (!r.family) throw new Error(`إجابة بلا مجموعة: ${r.id}`);
  return {id: r.id, family: r.family, question: r.question, answer: r.answer, spoken: r.spoken, keywords: [...new Set(r.keywords.map(normalize).filter(Boolean))], actions: (r.actions ?? []).map(a => parseAction(a, r.id)), run: parseRun(r.run, r.id)};
});
const byId = new Map(intents.map(i => [i.id, i]));
export function intent(id: string): Intent {
  const found = byId.get(id);
  if (!found) throw new Error(`إجابة غير موجودة: ${id}`);
  return found;
}
export const starters: Intent[] = content.starters.map(intent);
const outOfScope = [...new Set(content.outOfScope.map(normalize).filter(Boolean))];
const negations = [...new Set(content.negations.map(normalize).filter(Boolean))];

/** توحيد الكتابة للمطابقة فقط: حذف التشكيل والتطويل وعلامات الترقيم، وتوحيد الألف والياء والتاء المربوطة. */
export function normalize(text: string): string {
  return text
    .normalize("NFKC")
    .replace(/[ً-ٰٟۖ-ۭـ]/g, "")
    .replace(/[أإآٱ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه").replace(/ؤ/g, "و").replace(/ئ/g, "ي")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ").trim().toLowerCase();
}

// العبارة تُحسب إذا بدأت عند حد كلمة (تقبل لاحقة مثل «اقتباس» ← «اقتباسا»). الوزن = عدد كلماتها.
function score(text: string, phrases: string[]): number {
  const padded = ` ${text}`;
  let total = 0;
  for (const phrase of phrases) if (padded.includes(` ${phrase}`)) total += phrase.split(" ").length;
  return total;
}

export type Match =
  | {kind: "intent"; intent: Intent}
  | {kind: "clarify"; options: Intent[]; reason: "tie" | "compound"}
  | {kind: "negated"}
  | {kind: "out_of_scope"}
  | {kind: "unclear"; offerQuote: boolean};

/** يختار إجابة معدّة لطلب الزائر، أو يطلب التوضيح، أو يبيّن حدود المساعدة. لا يؤلف إجابة. */
export function matchRequest(input: string): Match {
  const text = normalize(input).slice(0, 300);
  const words = text ? text.split(" ").length : 0;
  if (!text) return {kind: "unclear", offerQuote: false};
  const ranked = intents.map(i => ({i, s: score(text, i.keywords)})).filter(r => r.s > 0).sort((a, b) => b.s - a.s);
  const out = score(text, outOfScope);
  const best = ranked[0];
  if (out > 0 && (!best || out > best.s)) return {kind: "out_of_scope"};
  // النفي («لا أريد فتح التفسير»، «بلاش»، «إلغاء») يمنع أي إجراء أو تخمين؛ نعرض خيارات بدلًا منه.
  if (score(text, negations) > 0) return {kind: "negated"};
  if (!best) return {kind: "unclear", offerQuote: words >= 2};
  // أفضل إجابة من كل مجموعة؛ التحية لا تُحسب طلبًا مستقلًا إذا جاء معها طلب آخر.
  const perFamily: {i: Intent; s: number}[] = [];
  for (const r of ranked) {
    const same = perFamily.find(p => p.i.family === r.i.family);
    // داخل المجموعة الواحدة عند التساوي نفضّل الإجابة التي لا تنفذ إجراءً.
    if (!same) perFamily.push(r); else if (r.s === same.s && same.i.run && !r.i.run) same.i = r.i;
  }
  const families = perFamily.length > 1 ? perFamily.filter(p => p.i.family !== "social") : perFamily;
  const top = families[0], next = families[1];
  // طلب مركب يجمع أمرين أحدهما إجراء: لا ننفذ أيًّا منهما قبل أن يختار الزائر.
  if (next && (top.i.run || next.i.run)) return {kind: "clarify", options: families.slice(0, 3).map(f => f.i), reason: "compound"};
  if (next && next.s === top.s) return {kind: "clarify", options: [top.i, next.i], reason: "tie"};
  return {kind: "intent", intent: top.i};
}
