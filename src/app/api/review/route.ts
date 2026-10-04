import { reviewQuote } from "@/lib/data";
import { InputError, json, quoteInput, readJson } from "@/lib/api";
export const runtime = "nodejs";
// لا يُسجَّل نص الاقتباس، ولا تُعرض رسائل الأخطاء الداخلية للعميل.
export async function POST(request: Request) {
  try {
    const read = await readJson(request, "الاقتباس أطول من الحد المتاح.");
    if (!read.ok) return read.response;
    const input = quoteInput(read.value);
    if (!input) return json({error: "أدخل اقتباسًا صالحًا."}, 400);
    try {return json(reviewQuote(input.quote, input.selection));}
    catch (e) {if (e instanceof InputError) return json({error: e.message}, 400); throw e;}
  } catch {return json({error: "تعذر الاتصال بمصدر المراجعة. حاول مرة أخرى."}, 503);}
}
