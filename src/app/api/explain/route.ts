import {reviewQuote,sourcePolicy} from "@/lib/data";
import {collectEvidence,EXPLANATION_NOTICE} from "@/lib/explanation";
import {InputError,json,quoteInput,readJson} from "@/lib/api";
export const runtime="nodejs";
export const maxDuration=60;
export async function POST(request:Request){
  try{
    const read=await readJson(request,"الطلب أطول من الحد المتاح.");
    if(!read.ok)return read.response;
    const input=quoteInput(read.value);
    if(!input)return json({error:"أدخل اقتباسًا صالحًا."},400);
    let result;try{result=reviewQuote(input.quote,input.selection);}catch(e){if(e instanceof InputError)return json({error:"تعذر تحديد الموضع."},400);throw e;}
    const evidence=collectEvidence(result,new Set(sourcePolicy.tafsir_books.filter(b=>b.aiEligible).map(b=>b.bookId)));
    if(!evidence.length)return json({status:"abstained",claims:[],sourceVersion:result.sourceVersion,notice:EXPLANATION_NOTICE,reason:!result.selected||result.selected.kind==="possible"?"اختر موضعًا مؤكدًا أولًا.":"لا تتوفر أدلة تفسير كافية للشرح المساعد لهذا الموضع."});
    // Owner chose original approved tafsir only. Never call a paid provider, even if an old key exists.
    return json({status:"abstained",claims:[],sourceVersion:result.sourceVersion,notice:EXPLANATION_NOTICE,reason:"توليد الشرح متوقف. اقرأ التفسير الأصلي الموثق في قسم التفسير ومصدره."});
  }catch{return json({error:"تعذر الاتصال بمصدر المراجعة. حاول مرة أخرى."},503);}
}
