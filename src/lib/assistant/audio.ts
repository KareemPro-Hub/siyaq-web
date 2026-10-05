// الردود المنطوقة: ملفات صوتية مسجّلة مسبقًا بصوت واحد (Achird من Gemini TTS)، ومستضافة في public/assistant-audio.
// النص المنطوق فصحى مشكولة، ويقول «لقطة شاشة» بدل «صورة» حتى لا تُسمع «سورة». لا آيات ولا نص من الزائر.
import manifest from "@/content/assistant-audio.json";
import {intents, messages} from "./intents";

export const AUDIO_BASE = "/assistant-audio/";
type Entry = {file: string; spoken: string};
const entries = manifest as Record<string, Entry>;

/** النص الذي يُمرَّر للنطق في اللوحة لكل مفتاح: رسالة، أو (spoken ?? answer) للإجابة. */
export function displayTextFor(key: string): string | undefined {
  const [kind, id] = [key.slice(0, 2), key.slice(2)];
  if (kind === "M.") return (messages as Record<string, string>)[id];
  const i = intents.find(x => x.id === id);
  return i ? (i.spoken ?? i.answer) : undefined;
}

const byText = new Map<string, string>();
for (const [key, e] of Object.entries(entries)) {
  const text = displayTextFor(key);
  if (!text) throw new Error(`ملف صوتي لنص غير موجود: ${key}`);
  byText.set(text, AUDIO_BASE + e.file);
}

/** رابط الملف الصوتي لرد معدّ، أو null إن لم يكن له تسجيل (فيظهر مكتوبًا فقط). */
export function clipFor(text: string): string | null {
  return byText.get(text) ?? null;
}
export const audioEntries = entries;
