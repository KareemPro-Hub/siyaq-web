import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";
import { Header, Footer } from "@/components/shell";
// Markazi Text (SIL OFL 1.1, src/fonts/LICENSE-MarkaziText.txt) replaces Harir, which lacked a web licence. size-adjust matches Harir's Arabic size.
const markazi = localFont({src: "../fonts/MarkaziText-wght.woff2", weight: "400 700", style: "normal", variable: "--font-markazi", display: "swap", adjustFontFallback: false, declarations: [{prop: "size-adjust", value: "113%"}]});
// Markazi Text lacks nine Quranic stop/section marks; keep those exact glyphs legible.
const quranMarks = localFont({src: "../fonts/QuranMarks.woff2", weight: "400", variable: "--font-quran-marks", display: "swap", adjustFontFallback: false, declarations: [{prop: "unicode-range", value: "U+06D6-06DC,U+06DE,U+06E9"}]});
const description = "راجع اقتباسًا قرآنيًا، واعرض نصه الأصلي وسياقه والتفسير المتاح من مصادر موثقة.";
// الأيقونات نسخ مصغرة من الشعار المعتمد (كان الأصل ١٫١ ميجابايت يُحمَّل أيقونةً). عنوان المعاينة ثابت على دومين سِياق المعتمد.
export const metadata: Metadata = {metadataBase: new URL("https://www.mysiyaq.com"), title: {default: "سِياق — افهم قبل أن تقتبس", template: "%s | سِياق"}, description, applicationName: "سِياق", icons: {icon: [{url: "/brand/siyaq-icon-48.png", sizes: "48x48", type: "image/png"}, {url: "/brand/siyaq-icon-192.png", sizes: "192x192", type: "image/png"}], apple: "/brand/siyaq-apple-icon-180.png"}, openGraph: {type: "website", locale: "ar", siteName: "سِياق", title: "سِياق — افهم قبل أن تقتبس", description, images: [{url: "/brand/siyaq-share-512.png", width: 512, height: 512, alt: "شعار سِياق"}]}, twitter: {card: "summary", title: "سِياق — افهم قبل أن تقتبس", description, images: ["/brand/siyaq-share-512.png"]}};
export default function Layout({children}: {children: React.ReactNode}) {
  return <html lang="ar" dir="rtl" className={`${markazi.variable} ${quranMarks.variable}`}><body><a className="skip-link" href="#main">انتقل إلى المحتوى</a><Header />{children}<Footer /></body></html>;
}
