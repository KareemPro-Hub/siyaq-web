import type {Metadata} from 'next';
import Link from 'next/link';

export const metadata: Metadata = {title: 'الدعم والمساعدة'};

export default function Support() {
  return <main id="main" className="reading-page"><div className="reading-inner">
    <h1>كيف نساعدك في سِياق ؟</h1>
    <p>للاستفسارات والملاحظات الفنية، تواصل معنا عبر البريد:</p>
    <p><a className="source-link" dir="ltr" href="mailto:Egy.Kareem.AI@gmail.com">Egy.Kareem.AI@gmail.com</a></p>
    <p>اذكر إصدار التطبيق ونوع جهازك وخطوات المشكلة. يمكنك إرفاق صورة للشاشة بعد إخفاء أي معلومات شخصية.</p>
    <section className="reading-section"><h2>البحث وقراءة الصور</h2>
      <p>النسخة الحالية مخصصة للاقتباسات القرآنية. اكتب الاقتباس أو استخرجه من صورة، ثم راجع النص قبل بدء البحث. البحث الجديد يحتاج اتصالًا بالإنترنت.</p>
    </section>
    <section className="reading-section"><h2>المحفوظات والتفسير</h2>
      <p>النتائج التي تحفظها في تطبيق الآيفون متاحة على جهازك دون اتصال. يُعرض التفسير الأصلي عند توفره؛ عدم توفره في الكتب الحالية لا يعني عدم وجود تفسير للآية.</p>
    </section>
    <section className="reading-section"><h2>الإبلاغ عن ملاحظة في المحتوى</h2>
      <p>أرسل اسم السورة ورقم الآية واسم المصدر، مع وصف الملاحظة. سِياق أداة بحث وتوثيق ولا يقدم فتاوى.</p>
    </section>
    <Link className="reading-cta" href="/privacy">سياسة الخصوصية</Link>
    <Link className="reading-cta" href="/">العودة إلى سِياق</Link>
  </div></main>;
}
