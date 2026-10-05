// الصوت في مساعد سِياق يعتمد على إمكانات المتصفح نفسه، دون مفاتيح أو خدمات مدفوعة:
// - التعرف على الكلام: Web Speech API ‏(SpeechRecognition). المتصفح يحدد طريقة المعالجة؛ Chrome مثلًا يرسل الصوت إلى خدمة Google.
// - النطق: speechSynthesis بأصوات الجهاز. لا ننطق إلا نصوص الإجابات المعدّة، ولا ننطق اقتباس المستخدم أبدًا.

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
export function listenOnce(onInterim: (text: string) => void, {timeoutMs = 12000, Ctor = recognitionCtor(), lang = recognitionLang()}: {timeoutMs?: number; Ctor?: RecognitionCtor | null; lang?: string} = {}): Listening | null {
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
    resolve(error && !text ? {ok: false, error} : text ? {ok: true, text} : {ok: false, error: error ?? "no-speech"});
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
  rec.onerror = e => {error = recognitionError(e.error); if (error === "aborted" || error === "denied" || error === "no-mic" || error === "language") finish();};
  rec.onend = finish;
  try {rec.start();} catch {error = "failed"; finish();}
  return {result, stop: () => {try {rec.stop();} catch {finish();}}, abort: () => {error = "aborted"; finalText = ""; interim = ""; try {rec.abort();} catch {} finish();}};
}

export type Speaking = {done: Promise<{ok: boolean}>; cancel(): void};
type AudioLike = {src: string; preload: string; currentTime: number; play(): Promise<void> | void; pause(): void; onended: (() => void) | null; onerror: (() => void) | null};
/** تشغيل ملف صوتي مسجّل مسبقًا ومستضاف مع الموقع. لا توليد صوت ولا اتصال بخدمة أثناء الزيارة.
 * ينتهي بانتهاء الملف أو الإلغاء أو الفشل؛ ok=false عند الفشل، فتبقى الردود مكتوبة فقط. */
export function playClip(url: string, make: () => AudioLike = () => new Audio() as unknown as AudioLike): Speaking {
  const audio = make();
  let finish!: (r: {ok: boolean}) => void;
  const done = new Promise<{ok: boolean}>(r => {finish = r;});
  let settled = false;
  const end = (ok: boolean) => {if (settled) return; settled = true; audio.onended = audio.onerror = null; finish({ok});};
  audio.onended = () => end(true);
  audio.onerror = () => end(false);
  audio.preload = "auto"; audio.src = url;
  try {Promise.resolve(audio.play()).catch(() => end(false));} catch {end(false);}
  return {done, cancel: () => {try {audio.pause(); audio.currentTime = 0;} catch {} end(true);}};
}
