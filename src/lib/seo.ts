import type {Metadata} from "next";

// الفهرسة مسموحة للصفحات التعريفية فقط، وعلى الدومين الأساسي فقط.
// نتائج المراجعة حالة مؤقتة داخل الرئيسية بلا رابط مستقل، وواجهات الخدمة وأي رابط فيه معاملات (?…) تبقى خارج الفهرسة.
// رابط Vercel القديم يبقى عاملًا لخدمة الآيفون دون تحويل، لكنه يرسل noindex حتى لا ينافس الدومين الأساسي.
export const SITE_HOST = "www.mysiyaq.com";
export const SITE_URL = `https://${SITE_HOST}`;
export const NOINDEX = "noindex, nofollow, noarchive";
// رمز التحقق من ملكية الموقع في Google Search Console (طريقة «علامة HTML» لخاصية https://www.mysiyaq.com/).
// يُنسخ من Search Console بحساب سِياق ويوضع هنا قبل النشر؛ فارغًا لا تُضاف أي علامة. الرمز علني بطبيعته وليس سرًا.
export const GOOGLE_SITE_VERIFICATION = "NFrSdwSUUaMNq4IDvPEfLSxLRTMWBU0oqauibBeqmrM";

export const INDEXABLE_PAGES = [
  {path: "/", title: "سِياق — مراجعة الاقتباس القرآني في سياقه", description: "اكتب اقتباسًا قرآنيًا أو اختر صورة، واعرف موضعه في المصحف مع الآيات المحيطة والتفسير الأصلي المتاح ومرجعه."},
  {path: "/sources", title: "مصادر النص القرآني والتفسير", description: "مصادر النص القرآني والتفسير في سِياق، وطبعاتها ونسخ بياناتها وحدود تغطيتها."},
  {path: "/methodology", title: "كيف يعمل: المطابقة والسياق والتفسير", description: "كيف يحدد سِياق موضع الاقتباس بمقارنة نصية، ويعرض السياق والتفسير الأصلي المسترجع، وحدود قراءة الصور."},
  {path: "/support", title: "الدعم والتواصل", description: "التواصل مع سِياق، وإرشادات البحث وقراءة الصور والإبلاغ عن ملاحظة في المحتوى."},
  {path: "/privacy", title: "سياسة الخصوصية", description: "كيف يتعامل موقع سِياق وتطبيق الآيفون مع الاقتباس والصورة والسجلات التقنية."},
] as const;
export type IndexablePath = (typeof INDEXABLE_PAGES)[number]["path"];

const PATHS = new Set<string>(INDEXABLE_PAGES.map(p => p.path));

/** هل يُسمح بفهرسة هذا الطلب؟ الدومين الأساسي + صفحة معتمدة + بلا معاملات. */
export function isIndexable(host: string | null, path: string, search: string): boolean {
  const h = (host ?? "").toLowerCase().replace(/:\d+$/, "");
  return h === SITE_HOST && PATHS.has(path) && search === "";
}

const SHARE_IMAGE = {url: "/brand/siyaq-share-512.png", width: 512, height: 512, alt: "شعار سِياق"};

/** العنوان والوصف والرابط الأساسي ومعاينة المشاركة لصفحة معتمدة. */
export function pageMetadata(path: IndexablePath): Metadata {
  const page = INDEXABLE_PAGES.find(p => p.path === path)!;
  const title = path === "/" ? {absolute: page.title} : page.title;
  const fullTitle = path === "/" ? page.title : `${page.title} | سِياق`;
  return {
    title,
    description: page.description,
    alternates: {canonical: path},
    openGraph: {type: "website", locale: "ar", siteName: "سِياق", url: path, title: fullTitle, description: page.description, images: [SHARE_IMAGE]},
    twitter: {card: "summary", title: fullTitle, description: page.description, images: [SHARE_IMAGE.url]},
  };
}
