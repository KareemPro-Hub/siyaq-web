"use client";
import {useEffect,useRef,useState} from "react";
import Link from "next/link";
import type {ReviewResult} from "@/lib/types";
import type {Explanation} from "@/lib/explanation";
export function EvidenceExplanation({result}:{result:ReviewResult}){
  const [output,setOutput]=useState<Explanation|null>(null);const [error,setError]=useState("");const [pending,setPending]=useState(false);const controller=useRef<AbortController|null>(null);
  useEffect(()=>()=>controller.current?.abort(),[]);
  async function explain(){
    controller.current?.abort();const request=new AbortController();controller.current=request;setPending(true);setError("");const timer=setTimeout(()=>request.abort(),50000);
    try{const response=await fetch("/api/explain",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({quote:result.quote,selection:result.selected?.id}),signal:request.signal});const data=await response.json();if(!response.ok)throw Error(data.error||"تعذر إعداد الشرح.");if(controller.current===request)setOutput(data);}
    catch(e){if(controller.current===request)setError(request.signal.aborted?"انتهت مهلة الشرح. حاول مرة أخرى.":e instanceof Error?e.message:"تعذر إعداد الشرح.");}
    finally{clearTimeout(timer);if(controller.current===request)setPending(false);}
  }
  return <section className="reading-sheet explanation-paper" aria-labelledby="explanation-title"><span className="eyebrow">قراءة مساعدة</span><h3 id="explanation-title">شرح من الأدلة المتاحة</h3><p className="reading-note">عند الطلب، نرسل نص الآية وأدلة التفسير إلى خدمة الذكاء الاصطناعي لتبسيطها. لا نرسل نص إدخالك الحر. <Link href="/privacy">الخصوصية</Link></p>{!output&&<button className="outline-button" type="button" disabled={pending||result.selected?.kind==="possible"} onClick={explain}>{pending?"جارٍ مراجعة الأدلة…":"اطلب شرحًا موثقًا"}</button>}{error&&<p role="alert" className="form-error">{error}</p>}<div aria-live="polite">{output&&(output.status==="abstained"?<p className="unavailable">{output.reason||"تعذر تقديم شرح يستند بوضوح إلى الأدلة المتاحة. راجع النص الأصلي."}</p>:output.claims.map((claim,i)=><article className="explanation-claim" key={i}><p>{claim.text}</p><blockquote>{claim.excerpt}</blockquote><a className="source-link" href={claim.evidence.url} target="_blank" rel="noopener noreferrer">{claim.evidence.bookName} — {claim.evidence.verseId}{claim.evidence.page!=null&&` — الصفحة ${new Intl.NumberFormat("ar-EG").format(claim.evidence.page)}`}</a></article>))}{output&&<p className="reading-note">{output.notice}</p>}</div></section>;
}
