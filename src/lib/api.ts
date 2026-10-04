// أدوات مشتركة لمساري الخدمة: قراءة جسم محدود الحجم وأخطاء إدخال آمنة العرض.
export const MAX_BODY_BYTES = 8192;
/** خطأ إدخال رسالته موجهة للمستخدم؛ أي خطأ آخر لا تُعرض رسالته. */
export class InputError extends Error {}
export const json = (data: unknown, status = 200) => Response.json(data, {status, headers: {"Cache-Control": "no-store"}});
type Read = {ok: true; value: unknown} | {ok: false; response: Response};
/** يتحقق من النوع، ويرفض الجسم الكبير قبل قراءته كاملًا (حسب Content-Length وأثناء القراءة). */
export async function readJson(request: Request, tooLarge: string): Promise<Read> {
  if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) return {ok: false, response: json({error: "صيغة الطلب غير مدعومة."}, 415)};
  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) return {ok: false, response: json({error: tooLarge}, 413)};
  const chunks: Uint8Array[] = []; let size = 0;
  const reader = request.body?.getReader();
  if (reader) {
    for (;;) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY_BYTES) {await reader.cancel().catch(() => {}); return {ok: false, response: json({error: tooLarge}, 413)};}
      chunks.push(value);
    }
  }
  const body = new TextDecoder().decode(chunks.length === 1 ? chunks[0] : Buffer.concat(chunks));
  try {return {ok: true, value: JSON.parse(body)};} catch {return {ok: false, response: json({error: "تعذر قراءة الطلب."}, 400)};}
}
/** شكل الطلب المشترك: quote نص، وselection نص اختياري. */
export function quoteInput(input: unknown): {quote: string; selection?: string} | null {
  if (!input || typeof input !== "object" || Array.isArray(input)) return null;
  const {quote, selection} = input as {quote?: unknown; selection?: unknown};
  if (typeof quote !== "string" || (selection !== undefined && selection !== null && typeof selection !== "string")) return null;
  return {quote, selection: typeof selection === "string" ? selection : undefined};
}
