import type { Metadata } from "next";
import Link from "next/link";
// Next يضيف noindex لهذه الصفحة تلقائيًا، والترويسة تمنع فهرستها أيضًا.
export const metadata: Metadata = {title: "الصفحة غير موجودة"};
export default function NotFound() {return <main id="main" className="reading-page"><div className="reading-inner"><h1>هذه الصفحة غير موجودة.</h1><Link className="reading-cta" href="/">العودة إلى سِياق</Link></div></main>;}
