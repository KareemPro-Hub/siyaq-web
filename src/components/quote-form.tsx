"use client";
import { ArrowLeft, LoaderCircle } from "lucide-react";
import type { RefObject } from "react";
const EXAMPLES = ["إن مع العسر يسرا", "لا تقربوا الصلاة", "الحمد لله رب العالمين"];
export function QuoteForm({quote, setQuote, submit, clear, pending, error, compact = false, inputRef}: {
  quote: string; setQuote: (text: string) => void; submit: () => void; clear: () => void;
  pending: boolean; error: string; compact?: boolean; inputRef: RefObject<HTMLTextAreaElement | null>;
}) {
  return <form className={`quote-form${compact ? " compact" : ""}`} onSubmit={e => {e.preventDefault(); submit();}} aria-busy={pending}>
    <div className="form-heading"><label htmlFor="quote">الاقتباس القرآني</label>{!compact && <button type="button" className="clear-button" onClick={clear} disabled={pending}>مسح النص</button>}</div>
    <div className="quote-field"><textarea ref={inputRef} id="quote" name="quote" dir="rtl" value={quote} onChange={e => setQuote(e.target.value)} maxLength={1000} rows={4} placeholder="ضع الاقتباس الذي تريد مراجعته…" aria-describedby="quote-hint quote-error" aria-invalid={Boolean(error)} onKeyDown={e => {if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {e.preventDefault(); submit();}}} /></div>
    <p id="quote-hint" className="field-hint">ضع آية أو جزءًا منها، بالتشكيل أو بدونه.</p>
    <p id="quote-error" role={error ? "alert" : undefined} className={error ? "form-error" : "visually-hidden"}>{error}</p>
    <div className="form-bottom">{!compact && <div className="examples"><p>جرّب مثالًا</p><div className="example-list">{EXAMPLES.map(text => <button key={text} type="button" onClick={() => {setQuote(text); inputRef.current?.focus();}} disabled={pending}>{text}</button>)}</div></div>}
    <button className="primary-button" type="submit" disabled={pending}>{pending ? <><LoaderCircle className="spinning" aria-hidden="true" /> جارٍ البحث في النص القرآني</> : <>{compact ? "مراجعة جديدة" : "راجع الاقتباس"}<ArrowLeft size={23} strokeWidth={1.8} aria-hidden="true" /></>}</button></div>
    <span className="visually-hidden" aria-live="polite">{pending ? "جارٍ مراجعة الاقتباس" : ""}</span>
  </form>;
}
