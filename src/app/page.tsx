import type { Metadata } from "next";
import { QuoteWorkbench } from "@/components/quote-workbench";
import { SITE_URL, pageMetadata } from "@/lib/seo";
export const metadata: Metadata = pageMetadata("/");
// اسم الموقع لمحركات البحث فقط، دون ادعاءات. النتائج حالة داخل الصفحة بلا رابط مستقل.
const website = {"@context": "https://schema.org", "@type": "WebSite", name: "سِياق", url: `${SITE_URL}/`, inLanguage: "ar"};
export default function Page() {return <><script type="application/ld+json" dangerouslySetInnerHTML={{__html: JSON.stringify(website)}} /><QuoteWorkbench /></>;}
