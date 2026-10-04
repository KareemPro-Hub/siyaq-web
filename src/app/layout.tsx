import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";
import { Header, Footer } from "@/components/shell";
// Markazi Text (SIL OFL 1.1, src/fonts/LICENSE-MarkaziText.txt) replaces Harir, which lacked a web licence. size-adjust matches Harir's Arabic size.
const markazi = localFont({src: "../fonts/MarkaziText-wght.woff2", weight: "400 700", style: "normal", variable: "--font-markazi", display: "swap", adjustFontFallback: false, declarations: [{prop: "size-adjust", value: "113%"}]});
// Markazi Text lacks nine Quranic stop/section marks; keep those exact glyphs legible.
const quranMarks = localFont({src: "../fonts/QuranMarks.woff2", weight: "400", variable: "--font-quran-marks", display: "swap", adjustFontFallback: false, declarations: [{prop: "unicode-range", value: "U+06D6-06DC,U+06DE,U+06E9"}]});
export const metadata: Metadata = {title: {default: "سِياق — افهم قبل أن تقتبس", template: "%s | سِياق"}, description: "راجع اقتباسًا قرآنيًا، واعرض نصه الأصلي وسياقه والتفسير المتاح من مصادر موثقة.", icons: {icon:"/brand/siyaq-logo.png", apple:"/brand/siyaq-logo.png"}};
export default function Layout({children}: {children: React.ReactNode}) {
  return <html lang="ar" dir="rtl" className={`${markazi.variable} ${quranMarks.variable}`}><body><a className="skip-link" href="#main">انتقل إلى المحتوى</a><Header />{children}<Footer /></body></html>;
}
