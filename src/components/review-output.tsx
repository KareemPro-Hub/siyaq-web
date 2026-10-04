"use client";
import {useState} from "react";
import {ArrowUpLeft, BookOpen} from "lucide-react";
import type {Candidate, ReviewResult} from "@/lib/types";
import {CopyButton} from "./copy-button";
import {dorarPassage, tafsirAyahURL, verseURL} from "@/lib/links";
export const arabicNumber = (n: number) => new Intl.NumberFormat("ar-EG", {useGrouping:false}).format(n);
export function reference(candidate: Candidate) {
  const v = candidate.verses[0];
  return `سورة ${v.surahName}، ${candidate.verses.length > 1 ? "الآيات" : "الآية"} ${candidate.verses.map(v => arabicNumber(v.ayah)).join("–")}`;
}
function IgnoredNote({result}: {result: ReviewResult}) {
  const ignored = result.search?.ignored ?? [];
  if (!ignored.length) return null;
  return <p className="muted" data-testid="ignored-note">أُهمل في البحث فقط (واقتباسك محفوظ كما كتبته): {ignored.join("، ")}</p>;
}
function MissingTafsir({verseId, result}: {verseId: string; result: ReviewResult}) {
  const [surah, ayah] = verseId.split(":").map(Number);
  const verse = result.selected?.verses.find(v => v.id === verseId);
  const books = (result.sources?.tafsir ?? []).map(b => b.name);
  const passage = dorarPassage(surah, ayah);
  const dorar = passage?.url;
  return <div className="unavailable" data-testid="tafsir-missing"><p>{books.length ? `لا يوجد نص تفسير محفوظ لهذه الآية في الكتب المحمّلة حاليًا (${books.join("، ")}). لم نعرض تفسير آية أخرى بدلًا منه.` : "لا يوجد نص تفسير محفوظ لهذه الآية في بيانات الخدمة الحالية، ولم نعرض تفسير آية أخرى بدلًا منه."}</p>{dorar && passage && <a className="source-link" data-testid="dorar-tafsir-passage" href={dorar} target="_blank" rel="noopener noreferrer">{`تفسير سورة ${verse?.surahName ?? arabicNumber(surah)}، الآيات ${arabicNumber(passage.firstAyah)}–${arabicNumber(passage.lastAyah)} في الدرر السنية`}<ArrowUpLeft/></a>}</div>;
}
export function ReviewOutput({result, choose, pending, fromImage = false}: {result: ReviewResult; choose:(id:string)=>void; pending:boolean; fromImage?: boolean}) {
  const [tab, setTab] = useState("verse");
  const ocrSuspect = fromImage || (result.search?.ignored ?? []).some(token => !token.startsWith("«"));
  const segmentMatch = result.search?.method === "segments";
  if (!result.selected) return <section className="reading-sheet choices-paper" aria-labelledby="choice-title">
    {result.status === "not_found" ? <><BookOpen size={38} className="empty-icon" aria-hidden="true"/><h3 id="choice-title">لم نعثر على موضع يمكن تأكيده.</h3>{ocrSuspect ? <p data-testid="ocr-suspect">قد توجد أخطاء في قراءة الصورة. صحّح الكلمات غير الواضحة في مربع الاقتباس ثم راجع مرة أخرى، أو اكتب الاقتباس بنفسك.</p> : <p>راجع الكتابة، أو جرّب جزءًا أوضح من الاقتباس. عدم العثور هنا لا يكفي وحده للحكم على مصدره.</p>}<IgnoredNote result={result}/><p className="muted">لا نعرض آية أو تفسيرًا تخمينيًا بدلًا من دليل.</p></> : <>
      <h3 id="choice-title">{result.status === "possible" ? "وجدنا مواضع متشابهة تحتاج مراجعتك." : "ورد الاقتباس في أكثر من موضع."}</h3><p>{result.status === "possible" ? (segmentMatch ? "لم يطابق الاقتباس كاملًا، لكن هذه المواضع تحتوي مقاطع طويلة منه. ليست مطابقة مؤكدة؛ اختر موضعًا لمقارنة الكلمات بالنص الأصلي." : "هذه احتمالات للمقارنة، وليست مطابقة مؤكدة. اختر موضعًا لعرض النص الأصلي.") : "اختر الموضع المقصود حتى نعرض الآيات المحيطة به."}</p>{ocrSuspect && result.status === "possible" && <p data-testid="ocr-suspect">قد توجد أخطاء في قراءة الصورة؛ قارن الكلمات قبل الاعتماد على الموضع.</p>}<IgnoredNote result={result}/>
      <div className="candidate-list">{result.candidates.map(c => <article key={c.id} className="candidate-row"><div><h4>{reference(c)}</h4><p className="quran-text candidate-verse">{c.verses.map(v=>v.text).join(" ﴿ ﴾ ")}</p></div><button className="outline-button" type="button" disabled={pending} onClick={()=>choose(c.id)} aria-label={`عرض الموضع: ${reference(c)}`}>عرض الموضع<ArrowUpLeft size={17} aria-hidden="true"/></button></article>)}</div>
      {result.candidateCount > result.candidates.length && <p className="muted">نعرض أول {arabicNumber(result.candidates.length)} موضعًا من {arabicNumber(result.candidateCount)}؛ أضف كلمات لتضييق البحث.</p>}
    </>}
  </section>;
  const selected = result.selected;
  const ids = new Set(selected.verses.map(v=>v.id));
  const tabs = [{id:"verse",label:"النص القرآني"},{id:"context",label:"السياق المحيط"},{id:"tafsir",label:"التفسير ومصدره"}];
  return <div className="output-stack"><p className={`match-note ${selected.kind === "possible" ? "possible-note" : ""}`}>{selected.kind === "full" ? "هذا الموضع يطابق الاقتباس بعد توحيد التشكيل والرسم في البحث." : selected.note}</p><section className="reading-sheet" aria-label="الآية والسياق والتفسير"><div role="tablist" aria-label="أقسام المراجعة" className="tabs">{tabs.map((item,i)=><button key={item.id} id={`${item.id}-tab`} type="button" role="tab" aria-selected={tab===item.id} aria-controls={`${item.id}-panel`} tabIndex={tab===item.id?0:-1} onClick={()=>setTab(item.id)} onKeyDown={e=>{if(["ArrowLeft","ArrowRight","Home","End"].includes(e.key)){e.preventDefault(); const n=e.key==="Home"?0:e.key==="End"?tabs.length-1:(i+(e.key==="ArrowLeft"?1:-1)+tabs.length)%tabs.length;setTab(tabs[n].id);document.getElementById(`${tabs[n].id}-tab`)?.focus();}}}>{item.label}</button>)}</div>
      <div id="verse-panel" role="tabpanel" aria-labelledby="verse-tab" tabIndex={0} hidden={tab!=="verse"}><p className="source-label">{reference(selected)}</p>{selected.verses.map(v=><p className="quran-text" key={v.id} data-testid="canonical-verse">{v.text}</p>)}<div className="verse-actions"><CopyButton text={`${selected.verses.map(v=>v.text).join("\n")}\n${reference(selected)}\nالمصدر: الموسوعة القرآنية ${selected.verses.map(v=>verseURL(v.surah,v.ayah)).filter(Boolean).join(" ، ")} — نسخة ${result.sources?.quran.version ?? result.sourceVersion}`} label="نسخ النص والمرجع"/></div><p className="reading-note">النص الأصلي محفوظ كما ورد في المصدر؛ تطبيع الكتابة للبحث فقط.</p>{selected.verses.map(v => {const url = verseURL(v.surah, v.ayah); return url && <a key={v.id} className="source-link" data-testid="verse-source-link" href={url} target="_blank" rel="noopener noreferrer">{selected.verses.length > 1 ? `افتح الآية ${arabicNumber(v.ayah)} في مصدرها` : "افتح الآية في مصدرها"}<ArrowUpLeft/></a>;})}<p className="book-detail">مصدر النص: {result.sources?.quran.name ?? "الموسوعة القرآنية"} — مصحف حفص · نسخة {result.sources?.quran.version ?? result.sourceVersion}</p><IgnoredNote result={result}/></div>
      <div id="context-panel" role="tabpanel" aria-labelledby="context-tab" tabIndex={0} hidden={tab!=="context"}><div>{result.context.map(v=><div key={v.id} className={`context-row ${ids.has(v.id)?"selected":""}`}><span aria-label={`الآية ${v.ayah}`}>{arabicNumber(v.ayah)}</span><p className="quran-text">{v.text}</p></div>)}</div><p className="reading-note">السياق المحيط يُعرض للمراجعة، ولا يحكم وحده على معنى الاقتباس.</p></div>
      <div id="tafsir-panel" role="tabpanel" aria-labelledby="tafsir-tab" tabIndex={0} hidden={tab!=="tafsir"}>{result.tafsir.map(group=><div key={group.verseId}>{result.tafsir.length>1&&<h3>الآية {arabicNumber(Number(group.verseId.split(":")[1]))}</h3>}{!group.entries.length?<MissingTafsir verseId={group.verseId} result={result}/>:group.entries.map((row,j)=>{const [surah, ayah] = group.verseId.split(":").map(Number); const location=tafsirAyahURL(row.bookId,surah,ayah);return <article key={j} className="tafsir-entry"><h3>{row.bookName}</h3><p className="book-detail">{row.author}{row.part&&` — الجزء ${row.part}`}{row.page!=null&&` — الصفحة ${arabicNumber(row.page)}`}</p><p>{row.text}</p>{location?<a className="source-link" data-testid="tafsir-source-link" href={location} target="_blank" rel="noopener noreferrer">افتح التفسير في مصدره<ArrowUpLeft/></a>:<p className="muted">رابط موضع هذا التفسير غير متاح.</p>}</article>;})}</div>)}{(result.sources?.tafsir.length ?? 0) > 0 && <p className="book-detail">نسخ بيانات التفسير: {result.sources!.tafsir.map(b => `${b.name} ${b.version}`).join("، ")}</p>}{result.tafsir.some(g=>g.entries.length>0)&&<p className="reading-note">نُقل التفسير من الكتاب المسمّى؛ إيراد الروايات فيه لا يعني أن سِياق صحّح أسانيدها.</p>}</div>
    </section>{result.differences.length>0&&<section className="reading-sheet difference-paper"><h3>مقارنة الألفاظ في الموضع المحتمل</h3><p className="reading-note">المشطوب من إدخالك، والمسطّر من المصدر. المقارنة دون تشكيل؛ الآية الأصلية أعلاه.</p><p className="word-diff">{result.differences.map((w,i)=>w.type==="input"?<del key={i}>{w.text} </del>:w.type==="source"?<ins key={i}>{w.text} </ins>:<span key={i}>{w.text} </span>)}</p></section>}</div>;
}
