import {NextResponse, type NextRequest} from "next/server";
import {NOINDEX, isIndexable, isSearchDiscoveryResource} from "@/lib/seo";
// الفهرسة للصفحات التعريفية المعتمدة على الدومين الأساسي فقط (src/lib/seo.ts)، مع إتاحة ملفي اكتشاف المحركات، وما عداها noindex:
// واجهات الخدمة، والروابط ذات المعاملات، وصفحة 404، والأصول، ورابط Vercel القديم (يبقى عاملًا للآيفون دون تحويل).
// الصفحات والخدمة بلا تخزين مؤقت، أما الأصول الثابتة فتُخزَّن: كان no-store يعيد تنزيل الشعار وأصول قراءة الصور (~٩ ميجابايت) في كل مرة.
const ONE_DAY = "public, max-age=86400, stale-while-revalidate=604800";
export function proxy(request: NextRequest){
  const path = request.nextUrl.pathname;
  const host = request.headers.get("host") ?? request.nextUrl.host;
  const response=NextResponse.next();
  if (!isIndexable(host, path, request.nextUrl.search) && !isSearchDiscoveryResource(host, path, request.nextUrl.search)) response.headers.set("X-Robots-Tag", NOINDEX);
  if (path.startsWith("/_next/static/") || path.startsWith("/_next/image")) return response; // ترويسات Next الافتراضية
  response.headers.set("Cache-Control", path.startsWith("/ocr/") || path.startsWith("/brand/") ? ONE_DAY : "no-store");
  return response;
}
