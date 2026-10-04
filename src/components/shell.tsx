"use client";
import Image from "next/image";
import Link from "next/link";
import {useRef} from "react";
import {X} from "lucide-react";
import {ABOUT_SOURCES, ABOUT_SOURCES_NOTE, DORAR_NOTE} from "@/lib/links";
export function Brand() {
  return <Link className="brand" href="/" aria-label="سِياق — الرئيسية"><Image className="brand-logo" src="/brand/siyaq-logo.png" alt="" width={48} height={48}/><span>سِياق</span></Link>;
}
export function AboutButton() {
  const dialog = useRef<HTMLDialogElement>(null);
  return <><button type="button" onClick={() => dialog.current?.showModal()}>عن سِياق</button><dialog ref={dialog} aria-label="عن سِياق"><div className="dialog-header"><h2>عن سِياق</h2><button type="button" onClick={() => dialog.current?.close()} aria-label="إغلاق عن سِياق"><X/></button></div><p className="dialog-intro">يساعدك سِياق على العثور على موضع الاقتباس القرآني، وقراءة الآية في سياقها، والرجوع إلى مصادرها.</p><h3 className="dialog-sources-title">ما يعرضه سِياق</h3><p>النص القرآني والآيات المحيطة به من المصدر المعتمد، والتفسير الأصلي عند توفره، مع مرجعه ورابط موضعه.</p><h3 className="dialog-sources-title">حدود المراجعة</h3><p>لا يقدم سِياق فتاوى أو تفسيرًا مولّدًا. نتائج التشابه اقتراحات تحتاج إلى تحقق، ولا تثبت صحة الاقتباس. والنص المستخرج من الصورة مسودة يجب مراجعتها قبل البحث.</p><h3 className="dialog-sources-title">المصادر</h3><ul className="source-list">{ABOUT_SOURCES.map(source => <li key={source.url}><h3>{source.title}</h3><p>{source.role}</p><a className="source-link" href={source.url} target="_blank" rel="noopener noreferrer">رابط المصدر</a></li>)}</ul><p className="dialog-small">{ABOUT_SOURCES_NOTE}</p><p className="dialog-small">{DORAR_NOTE}</p><Link className="source-link" href="/sources" onClick={() => dialog.current?.close()}>تفاصيل المصادر والطبعات</Link><p>أُرسل تطبيق سِياق للآيفون إلى Apple للمراجعة. لاحقًا: الأحاديث النبوية الموثقة.</p><Link className="source-link" href="/privacy" onClick={() => dialog.current?.close()}>الخصوصية</Link></dialog></>;
}
export function Header() {
  return <header className="header wrap"><Brand/><nav aria-label="التنقل الرئيسي"><Link href="/#method">كيف يعمل</Link><Link href="/sources">المصادر</Link><AboutButton/></nav><Link href="/#review" className="button header-cta">راجع اقتباسًا</Link></header>;
}
export function Footer() {
  return <footer className="wrap"><Brand/><p>أُرسل تطبيق الآيفون إلى Apple للمراجعة. لاحقًا: الأحاديث النبوية الموثقة.</p><AboutButton/><nav className="footer-links" aria-label="المعلومات والمساعدة"><Link href="/sources">المصادر</Link><Link href="/methodology">كيف يعمل</Link><Link href="/support">الدعم</Link><Link href="/privacy">الخصوصية</Link></nav></footer>;
}
