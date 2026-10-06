// الصوت في مساعد سِياق يعتمد على إمكانات المتصفح نفسه، دون مفاتيح أو خدمات مدفوعة:
// - التعرف على الكلام: Web Speech API ‏(SpeechRecognition). المتصفح يحدد طريقة المعالجة؛ Chrome مثلًا يرسل الصوت إلى خدمة Google.
// - الردود المسموعة: تسجيلات معدّة ومستضافة مع الموقع. لا ننطق الآيات أو اقتباس المستخدم أبدًا.

export type RecognitionErrorKind = "denied" | "no-speech" | "no-mic" | "network" | "language" | "aborted" | "failed";
export type RecognitionResult = {ok: true; text: string} | {ok: false; error: RecognitionErrorKind};

type RecognitionEvent = {resultIndex: number; results: ArrayLike<ArrayLike<{transcript: string}> & {isFinal: boolean}>};
export type RecognitionLike = {
  lang: string; continuous: boolean; interimResults: boolean; maxAlternatives: number;
  onresult: ((e: RecognitionEvent) => void) | null; onerror: ((e: {error: string}) => void) | null; onend: (() => void) | null;
  start(): void; stop(): void; abort(): void;
};
type RecognitionCtor = new () => RecognitionLike;

export function recognitionCtor(win: unknown = typeof window === "undefined" ? undefined : window): RecognitionCtor | null {
  const w = win as {SpeechRecognition?: RecognitionCtor; webkitSpeechRecognition?: RecognitionCtor} | undefined;
  return w?.SpeechRecognition ?? w?.webkitSpeechRecognition ?? null;
}

/** تحويل أخطاء المتصفح إلى حالات مفهومة؛ لا إعادة تشغيل تلقائية في أي حالة. */
export function recognitionError(code: string): RecognitionErrorKind {
  switch (code) {
    case "not-allowed": case "service-not-allowed": return "denied";
    case "no-speech": return "no-speech";
    case "audio-capture": return "no-mic";
    case "network": return "network";
    case "language-not-supported": case "bad-grammar": return "language";
    case "aborted": return "aborted";
    default: return "failed";
  }
}

/** لغة التعرف: لغة المتصفح إن كانت عربية، وإلا العربية الفصحى المعتمدة في أغلب المتصفحات ar-SA. */
export function recognitionLang(languages: readonly string[] = typeof navigator === "undefined" ? [] : navigator.languages ?? []): string {
  const arabic = languages.find(l => /^ar(-|$)/i.test(l) && l.includes("-"));
  return arabic ?? "ar-SA";
}

export type Listening = {result: Promise<RecognitionResult>; stop(): void; abort(): void};
/** استماع لمرة واحدة. ينتهي بنص نهائي أو بخطأ، أو بعد مهلة؛ ولا يعيد التشغيل بنفسه. */
export function listenOnce(onInterim: (text: string) => void, {timeoutMs = 30000, Ctor = recognitionCtor(), lang = recognitionLang()}: {timeoutMs?: number; Ctor?: RecognitionCtor | null; lang?: string} = {}): Listening | null {
  if (!Ctor) return null;
  const rec = new Ctor();
  rec.lang = lang; rec.continuous = false; rec.interimResults = true; rec.maxAlternatives = 1;
  let finalText = "", interim = "", error: RecognitionErrorKind | null = null, done = false;
  let resolve!: (r: RecognitionResult) => void;
  const result = new Promise<RecognitionResult>(r => {resolve = r;});
  const finish = () => {
    if (done) return; done = true; clearTimeout(timer);
    rec.onresult = rec.onerror = rec.onend = null;
    const text = (finalText || interim).trim();
    resolve(error ? {ok: false, error} : text ? {ok: true, text} : {ok: false, error: error ?? "no-speech"});
  };
  const timer = setTimeout(() => {if (!error) error = "no-speech"; try {rec.abort();} catch {} finish();}, timeoutMs);
  rec.onresult = e => {
    interim = "";
    for (let i = e.resultIndex; i < e.results.length; i++) {
      const r = e.results[i];
      if (r.isFinal) finalText += r[0].transcript; else interim += r[0].transcript;
    }
    onInterim((finalText + interim).trim());
  };
  rec.onerror = e => {error = recognitionError(e.error); finish();};
  rec.onend = finish;
  try {rec.start();} catch {error = "failed"; finish();}
  return {result, stop: () => {try {rec.stop();} catch {finish();}}, abort: () => {error = "aborted"; finalText = ""; interim = ""; try {rec.abort();} catch {} finish();}};
}

export type Speaking = {done: Promise<{ok: boolean}>; cancel(): void};
type AudioLike = {src: string; preload: string; currentTime: number; play(): Promise<void> | void; pause(): void; onended: (() => void) | null; onerror: (() => void) | null};
/** تشغيل ملف صوتي مسجّل مسبقًا ومستضاف مع الموقع. لا توليد صوت ولا اتصال بخدمة أثناء الزيارة.
 * ينتهي بانتهاء الملف أو الإلغاء أو الفشل؛ ok=false عند الفشل، فتبقى الردود مكتوبة فقط. */
// نخزّن تسجيلات الردود فقط في ذاكرة الصفحة؛ لا صوت أو نص من الزائر.
const clipCache = new Map<string, Blob>();
export function playClip(url: string, make: () => AudioLike = () => new Audio() as unknown as AudioLike, {buffer = typeof window !== "undefined", onStart, timeoutMs = 90000}: {buffer?: boolean; onStart?: () => void; timeoutMs?: number} = {}): Speaking {
  const audio = make(), controller = new AbortController();
  let finish!: (r: {ok: boolean}) => void;
  const done = new Promise<{ok: boolean}>(r => {finish = r;});
  let settled = false, objectUrl: string | null = null;
  const end = (ok: boolean) => {
    if (settled) return; settled = true; clearTimeout(timer);
    controller.abort(); audio.onended = audio.onerror = null;
    try {audio.pause();} catch {}
    if (objectUrl) URL.revokeObjectURL(objectUrl);
    finish({ok});
  };
  const timer = setTimeout(() => end(false), timeoutMs);
  audio.onended = () => end(true); audio.onerror = () => end(false); audio.preload = "auto";
  const play = async () => {
    try {
      if (buffer) {
        let blob = clipCache.get(url);
        if (!blob) {
          const response = await fetch(url, {signal: controller.signal, cache: "force-cache"});
          if (!response.ok) throw new Error("audio unavailable");
          blob = await response.blob();
          if (!blob.size) throw new Error("empty audio");
          if (settled) return;
          if (clipCache.size >= 40) clipCache.delete(clipCache.keys().next().value!);
          clipCache.set(url, blob);
        }
        if (settled) return;
        objectUrl = URL.createObjectURL(blob); audio.src = objectUrl;
      } else audio.src = url;
      if (settled) return;
      await audio.play();
      if (!settled) onStart?.();
    } catch {end(false);}
  };
  void play();
  return {done, cancel: () => {end(true); try {audio.currentTime = 0;} catch {}}};
}
