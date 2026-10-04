import type { MetadataRoute } from "next";
import { INDEXABLE_PAGES, SITE_URL } from "@/lib/seo";
// الصفحات المعتمدة فقط، بروابط الدومين الأساسي.
export default function sitemap(): MetadataRoute.Sitemap {
  return INDEXABLE_PAGES.map(p => ({url: p.path === "/" ? `${SITE_URL}/` : `${SITE_URL}${p.path}`}));
}
