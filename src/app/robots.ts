import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/seo";
// الزحف مسموح للصفحات، وممنوع لواجهات الخدمة. منع الفهرسة نفسه في ترويسة X-Robots-Tag (src/proxy.ts)،
// لأن robots.txt يمنع الزحف لا الفهرسة، والصفحة الممنوعة من الزحف لا تُقرأ ترويستها.
export default function robots(): MetadataRoute.Robots {
  return {rules: {userAgent: "*", allow: "/", disallow: "/api/"}, sitemap: `${SITE_URL}/sitemap.xml`};
}
