import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";
import { Header, Footer } from "@/components/shell";
// خطا الموقع (SIL OFL 1.1، الرخص في src/fonts) بملفاتهما الأصلية دون تعديل، مستضافان محليًا:
// شهرزاد الجديد (SIL Global) للواجهة والعناوين والتفسير بأوزانه الحقيقية ٤٠٠ و٥٠٠ و٧٠٠،
// وأميري قرآن (Khaled Hosny) للنص القرآني الأصلي فقط بوزنه الوحيد ٤٠٠. الخطان يغطيان كل حروف وعلامات النص المحمّل.
const scheherazade = localFont({src: [{path: "../fonts/ScheherazadeNew-Regular.ttf", weight: "400"}, {path: "../fonts/ScheherazadeNew-Medium.ttf", weight: "500"}, {path: "../fonts/ScheherazadeNew-Bold.ttf", weight: "700"}], style: "normal", variable: "--font-scheherazade", display: "swap", adjustFontFallback: false});
const amiriQuran = localFont({src: "../fonts/AmiriQuran-Regular.ttf", weight: "400", style: "normal", variable: "--font-amiri-quran", display: "swap", adjustFontFallback: false});
const description = "راجع اقتباسًا قرآنيًا، واعرض نصه الأصلي وسياقه والتفسير المتاح من مصادر موثقة.";
// الأيقونات نسخ مصغرة من الشعار المعتمد (كان الأصل ١٫١ ميجابايت يُحمَّل أيقونةً). عنوان المعاينة ثابت على دومين سِياق المعتمد.
export const metadata: Metadata = {metadataBase: new URL("https://www.mysiyaq.com"), title: {default: "سِياق — افهم قبل أن تقتبس", template: "%s | سِياق"}, description, applicationName: "سِياق", icons: {icon: [{url: "/brand/siyaq-icon-48.png", sizes: "48x48", type: "image/png"}, {url: "/brand/siyaq-icon-192.png", sizes: "192x192", type: "image/png"}], apple: "/brand/siyaq-apple-icon-180.png"}, openGraph: {type: "website", locale: "ar", siteName: "سِياق", title: "سِياق — افهم قبل أن تقتبس", description, images: [{url: "/brand/siyaq-share-512.png", width: 512, height: 512, alt: "شعار سِياق"}]}, twitter: {card: "summary", title: "سِياق — افهم قبل أن تقتبس", description, images: ["/brand/siyaq-share-512.png"]}};
export default function Layout({children}: {children: React.ReactNode}) {
  return <html lang="ar" dir="rtl" className={`${scheherazade.variable} ${amiriQuran.variable}`}><body><a className="skip-link" href="#main">انتقل إلى المحتوى</a><Header />{children}<Footer /></body></html>;
}
