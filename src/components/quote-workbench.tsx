"use client";
import Image from "next/image";
import Link from "next/link";
import {useEffect, useRef, useState} from "react";
import {Eraser} from "lucide-react";
import type {ReviewResult} from "@/lib/types";
import {BrandIcon} from "./brand-icon";
import {ReviewOutput} from "./review-output";
import {ImageReader} from './image-reader';
export function QuoteWorkbench() {
  const [quote, setQuote] = useState("");
  const [result, setResult] = useState<ReviewResult | null>(null);
  const [pending, setPending] = useState(false);
  const [imagePending,setImagePending] = useState(false);
  const [error, setError] = useState("");
  // طلب فشل بسبب الاتصال أو المهلة: نعرض «إعادة المحاولة» ونحفظ الاقتباس والاختيار كما هما.
  const [retry, setRetry] = useState<{selection?: string} | null>(null);
  // هل جاء النص من قراءة صورة؟ يميّز «قد توجد أخطاء في قراءة الصورة» عن «لم نجد تطابقًا».
  const [fromImage, setFromImage] = useState(false);
  const controller = useRef<AbortController | null>(null);
  const inFlight = useRef(false);
  const input = useRef<HTMLTextAreaElement>(null);
  const output = useRef<HTMLElement>(null);
  useEffect(() => () => controller.current?.abort(), []);
  async function submit(selection?: string) {
    // طلب واحد في الوقت نفسه: الضغط المتكرر أو الإرسال المباشر للنموذج أثناء الانتظار لا يرسل طلبًا ثانيًا.
    if (inFlight.current) return;
    const text = selection && result ? result.quote : quote;
    if (!text.trim()) {setError("ضع الاقتباس أولًا."); input.current?.focus(); return;}
    controller.current?.abort();
    const current = new AbortController(); controller.current = current;
    let timedOut = false;
    const timeout = setTimeout(() => {timedOut = true; current.abort();}, 15000);
    inFlight.current = true;
    setPending(true); setError(""); setRetry(null);
    if (typeof navigator !== "undefined" && navigator.onLine === false) {clearTimeout(timeout); setPending(false); setError("لا يوجد اتصال بالإنترنت الآن؛ اقتباسك محفوظ. اتصل ثم أعد المحاولة."); setRetry({selection}); inFlight.current = false; return;}
    try {
      const response = await fetch('/api/review', {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({quote:text,...(selection?{selection}:{})}), signal:current.signal});
      // ردّ ليس JSON (صفحة خطأ من الاستضافة مثلًا) هو تعطل خدمة، لا «لم نجد تطابقًا» ولا رسالة تحليل تقنية.
      const data = await response.json().catch(() => null);
      if (!data || response.status >= 500) {const failure = new Error(data?.error ?? "تعذر الوصول إلى خدمة المراجعة الآن؛ لم نحكم على الاقتباس. حاول مرة أخرى."); failure.name = "ServiceError"; throw failure;}
      if (!response.ok) throw new Error(data.error ?? "تعذر إتمام المراجعة.");
      if (controller.current !== current) return;
      setResult(data as ReviewResult);
      requestAnimationFrame(() => {output.current?.focus(); output.current?.scrollIntoView({block:"start", behavior:"instant"});});
    } catch (e) {
      if (controller.current === current) {
        const network = !(e instanceof Error) || ["AbortError", "TypeError", "ServiceError"].includes(e.name);
        setError(timedOut ? "استغرقت المراجعة وقتًا أطول من المعتاد، وقد يكون الاتصال ضعيفًا. اقتباسك محفوظ؛ أعد المحاولة." : network ? (e instanceof Error && e.name === "ServiceError" ? e.message : "تعذر الاتصال بخدمة المراجعة؛ لم نحكم على الاقتباس. اقتباسك محفوظ؛ أعد المحاولة.") : (e as Error).message);
        if (network || timedOut) setRetry({selection});
      }
    } finally {clearTimeout(timeout); if (controller.current === current) {setPending(false); inFlight.current = false;}}
  }
  function edit(text: string) {
    controller.current?.abort(); controller.current = null; inFlight.current = false;
    setQuote(text); setPending(false); setError(""); setRetry(null); setResult(null);
  }
  function back() {edit(result?.quote ?? quote); requestAnimationFrame(() => input.current?.focus());}
  return <main id="main">
    <noscript><p className="wrap">فعّل JavaScript لاستخدام المراجعة. يمكنك قراءة المنهج والمصادر دون تفعيله.</p></noscript>
    <section className="hero" aria-labelledby="hero-title"><div className="wrap hero-inner"><div className="hero-copy"><h1 id="hero-title">اقرأ الآية،<br/>وافهمها في سياقها.</h1><p>راجع الاقتباس القرآني، واقرأ النص كاملًا،<br/>وسياقه والتفسير الموثق بمصدره.</p><a className="button" href="#review">ابدأ المراجعة <BrandIcon name="arrow"/></a></div><div className="hero-art"><div className="icon-orbit" aria-hidden="true"/>{([['mint','book'],['coral','quote'],['purple','check']] as const).map(([color,name]) => <span className={`orbit-symbol orbit-${name} ${color}`} aria-hidden="true" key={name}><BrandIcon name={name}/></span>)}<Image src="/brand/book-lens-approved.png" alt="كتاب مفتوح وعدسة للمراجعة والرجوع إلى المصدر" width={1536} height={1024} sizes="(max-width:700px) 350px, 500px" preload/></div></div><svg className="hero-wave" viewBox="0 0 1440 72" preserveAspectRatio="none" aria-hidden="true"><path d="M0 40C180 70 320 20 480 27S780 80 960 39 1260 30 1440 12V72H0Z"/></svg></section>
    <section className="review wrap" id="review" aria-labelledby="review-title"><div className="review-intro"><span className="section-label">المراجعة</span><h2 id="review-title">من الاقتباس <br/>إلى المعنى.</h2><p>النص القرآني أولًا، ثم الآيات المحيطة،<br/>ثم التفسير المتاح بمصدره.</p><div className="review-stages"><span className="mint"><BrandIcon name="book"/> النص القرآني</span><span className="coral"><BrandIcon name="quote"/> السياق المحيط</span><span className="purple"><BrandIcon name="check"/> التفسير ومصدره</span></div></div><div className="review-tool"><form className="search-shell" aria-label="مراجعة الاقتباس" onSubmit={e => {e.preventDefault(); void submit();}} aria-busy={pending}><label htmlFor="quote">ما الاقتباس الذي تريد مراجعته ؟</label><textarea id="quote" ref={input} value={quote} onChange={e => edit(e.target.value)} placeholder="اكتب الاقتباس القرآني هنا…" maxLength={1000} disabled={imagePending} spellCheck={false} aria-describedby="review-note feedback"/><div className="toolbar"><div className="actions"><button className="icon-button" type="button" aria-label="مسح الاقتباس" disabled={!quote || imagePending} onClick={() => {edit(""); setFromImage(false); input.current?.focus();}}><Eraser/></button></div><button className="button" type="submit" disabled={pending || imagePending || !quote.trim()}>{pending ? "جارٍ المراجعة…" : "راجع الاقتباس"}<BrandIcon name="arrow"/></button></div></form><p id="feedback" className="feedback" role={error ? "alert" : "status"} aria-live="polite">{error || (pending ? "نبحث عن موضع الاقتباس في النص المعتمد…" : "")}</p>{retry && !pending && <button type="button" className="outline-button retry-button" onClick={() => void submit(retry.selection)}>إعادة المحاولة</button>}<ImageReader onBusyChange={setImagePending} busy={pending} onText={text=>{edit(text);setFromImage(true);requestAnimationFrame(()=>input.current?.focus());}}/><div className="examples"><span>جرّب مثالًا</span>{["إن مع العسر يسرا","لا تقربوا الصلاة"].map(text => <button type="button" key={text} disabled={imagePending} onClick={() => {edit(text); setFromImage(false); input.current?.focus();}}>{text}</button>)}</div><p id="review-note" className="preview-note">المراجعة في القرآن كاملًا. تغطية التفسير جزئية، ونوضح غيابه.</p></div></section>
    {result && <section ref={output} id="result" className="result" aria-label="نتيجة مراجعة الاقتباس" tabIndex={-1}><div className="result-heading"><div><p className="eyeline">مراجعة الاقتباس</p><h2>{result.selected?.kind === "possible" ? "موضع محتمل للمقارنة" : result.selected ? "الاقتباس في موضعه" : "نتيجة البحث"}</h2></div><button className="text-button" type="button" onClick={back}>العودة للبحث <BrandIcon name="arrow"/></button></div><ReviewOutput key={(result.selected?.id??"choices")+result.quote} result={result} fromImage={fromImage} choose={id => void submit(id)} pending={pending}/></section>}
    <section className="method" id="method" aria-labelledby="method-title"><div className="wrap"><span className="section-label">كيف يعمل</span><h2 id="method-title">اقرأ ما وراء الاقتباس.</h2><ol className="method-steps">{([['mint','book','ضع الاقتباس','اكتب النص الذي تريد مراجعته.'],['coral','quote','اقرأ الآية في سياقها','راجع النص القرآني والآيات المحيطة به.'],['purple','check','ارجع إلى المصدر','اقرأ التفسير المتاح مع اسم الكتاب ومرجعه.']] as const).map(([color,icon,title,body]) => <li key={title}><span className={`step-icon ${color}`}><BrandIcon name={icon}/></span><div><h3>{title}</h3><p>{body}</p></div></li>)}</ol><Link className="source-cta" href="/sources">تعرّف على المصادر <BrandIcon name="arrow"/></Link></div></section>
  </main>;
}
