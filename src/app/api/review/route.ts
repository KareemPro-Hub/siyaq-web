import { reviewQuote } from "@/lib/data";
export const runtime = "nodejs";
const response = (data: unknown, status = 200) => Response.json(data, {status, headers: {"Cache-Control": "no-store"}});
export async function POST(request: Request) {
  try {
    if (!request.headers.get("content-type")?.includes("application/json")) return response({error: "صيغة الطلب غير مدعومة."}, 415);
    const body = await request.text();
    if (body.length > 8192) return response({error: "الاقتباس أطول من الحد المتاح."}, 413);
    let input: unknown;
    try {input = JSON.parse(body);} catch {return response({error: "تعذر قراءة الطلب."}, 400);}
    if (!input || typeof input !== "object" || Array.isArray(input)) return response({error: "أدخل اقتباسًا صالحًا."}, 400);
    const {quote, selection} = input as {quote?: unknown; selection?: unknown};
    if (typeof quote !== "string" || (selection !== undefined && typeof selection !== "string")) return response({error: "أدخل اقتباسًا صالحًا."}, 400);
    try {return response(reviewQuote(quote, selection as string | undefined));}
    catch (e) {return response({error: e instanceof Error ? e.message : "تعذر مراجعة الاقتباس."}, 400);}
  } catch {return response({error: "تعذر الاتصال بمصدر المراجعة. حاول مرة أخرى."}, 503);}
}
