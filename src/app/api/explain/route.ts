import {reviewQuote,sourcePolicy} from "@/lib/data";
import {collectEvidence,EXPLANATION_NOTICE} from "@/lib/explanation";
export const runtime="nodejs";
export const maxDuration=60;
const response=(data:unknown,status=200)=>Response.json(data,{status,headers:{"Cache-Control":"no-store"}});
export async function POST(request:Request){
  if(!request.headers.get("content-type")?.includes("application/json"))return response({error:"صيغة الطلب غير مدعومة."},415);
  let input:unknown;
  try{const raw=await request.text();if(raw.length>8192)return response({error:"الطلب أطول من الحد المتاح."},413);input=JSON.parse(raw);}catch{return response({error:"تعذر قراءة الطلب."},400);}
  if(!input||typeof input!=="object"||Array.isArray(input))return response({error:"أدخل اقتباسًا صالحًا."},400);
  const {quote,selection}=input as {quote?:unknown;selection?:unknown};
  if(typeof quote!=="string"||(selection!==undefined&&typeof selection!=="string"))return response({error:"أدخل اقتباسًا صالحًا."},400);
  let result;try{result=reviewQuote(quote,selection as string|undefined);}catch{return response({error:"تعذر تحديد الموضع."},400);}
  const evidence=collectEvidence(result,new Set(sourcePolicy.tafsir_books.filter(b=>b.aiEligible).map(b=>b.bookId)));
  if(!evidence.length)return response({status:"abstained",claims:[],sourceVersion:result.sourceVersion,notice:EXPLANATION_NOTICE,reason:!result.selected||result.selected.kind==="possible"?"اختر موضعًا مؤكدًا أولًا.":"لا تتوفر أدلة تفسير كافية للشرح المساعد لهذا الموضع."});
  // Owner chose original approved tafsir only. Never call a paid provider, even if an old key exists.
  return response({status:"abstained",claims:[],sourceVersion:result.sourceVersion,notice:EXPLANATION_NOTICE,reason:"توليد الشرح متوقف. اقرأ التفسير الأصلي الموثق في قسم التفسير ومصدره."});
}
