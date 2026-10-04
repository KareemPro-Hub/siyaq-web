import {NextResponse, type NextRequest} from "next/server";
// الموقع مفتوح بقرار المالك، والفهرسة ممنوعة. الصفحات والخدمة بلا تخزين مؤقت،
// أما الأصول الثابتة فتُخزَّن: كان no-store يعيد تنزيل الشعار وأصول قراءة الصور (~٩ ميجابايت) في كل مرة.
const ONE_DAY = "public, max-age=86400, stale-while-revalidate=604800";
export function proxy(request: NextRequest){
  const path = request.nextUrl.pathname;
  const response=NextResponse.next();
  response.headers.set("X-Robots-Tag","noindex, nofollow, noarchive");
  if (path.startsWith("/_next/static/") || path.startsWith("/_next/image")) return response; // ترويسات Next الافتراضية
  response.headers.set("Cache-Control", path.startsWith("/ocr/") || path.startsWith("/brand/") ? ONE_DAY : "no-store");
  return response;
}
