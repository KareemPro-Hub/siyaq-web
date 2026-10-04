// روابط مباشرة إلى موضع النص والتفسير. الأنماط فُحصت بعناوين الصفحات الفعلية (سجل-التحقق-من-الروابط.md):
// /surah/1/{سورة}/{آية} = الآية نفسها في مصحف حفص؛ /surah/{رقم} وحده يفتح مصحفًا آخر بهذا الرقم.
// /tafsir/{مسار السورة}/{آية}?book={كتاب} = تفسير الآية من الكتاب المحدد؛ الصفحة المطبوعة للتوثيق فقط.
// مقاطع الدرر تُربط بحدود الآيات المفحوصة، ولا تُخمّن من رقم الآية أو تُستبدل بفهرس السورة.
export const AYAH_COUNTS = [7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,30,52,52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,5,4,5,6];
export const VERIFIED_TAFSIR_BOOKS = new Set([269, 27758]);
export function verseURL(surah: number, ayah: number): string | null {
  if (!Number.isInteger(surah) || !Number.isInteger(ayah) || surah < 1 || surah > 114 || ayah < 1 || ayah > AYAH_COUNTS[surah - 1]) return null;
  return `https://quranpedia.net/surah/1/${surah}/${ayah}`;
}
// المسارات الرسمية للسور١١٤، فُحصت من تحويلات المصدر بتاريخ٣ أكتوبر٢٠٢٦.
export const TAFSIR_SURAH_SLUGS = ["al-fatiha", "al-baqara", "aal-imran", "an-nisa", "al-maida", "al-anam", "al-araf", "al-anfal", "at-tawba", "yunus", "hud", "yusuf", "ar-rad", "ibrahim", "al-hijr", "an-nahl", "al-isra", "al-kahf", "maryam", "ta-ha", "al-anbiya", "al-hajj", "al-muminun", "an-nur", "al-furqan", "ash-shuara", "an-naml", "al-qasas", "al-ankabut", "ar-rum", "luqman", "as-sajda", "al-ahzab", "saba", "fatir", "ya-sin", "as-saffat", "sad", "az-zumar", "ghafir", "fussilat", "ash-shura", "az-zukhruf", "ad-dukhan", "al-jathiya", "al-ahqaf", "muhammad", "al-fath", "al-hujurat", "qaf", "adh-dhariyat", "at-tur", "an-najm", "al-qamar", "ar-rahman", "al-waqia", "al-hadid", "al-mujadila", "al-hashr", "al-mumtahina", "as-saff", "al-jumua", "al-munafiqun", "at-taghabun", "at-talaq", "at-tahrim", "al-mulk", "al-qalam", "al-haaqqa", "al-maarij", "nuh", "al-jinn", "al-muzzammil", "al-muddaththir", "al-qiyama", "al-insan", "al-mursalat", "an-naba", "an-naziat", "abasa", "at-takwir", "al-infitar", "al-mutaffifin", "al-inshiqaq", "al-buruj", "at-tariq", "al-ala", "al-ghashiya", "al-fajr", "al-balad", "ash-shams", "al-layl", "ad-duha", "ash-sharh", "at-tin", "al-alaq", "al-qadr", "al-bayyina", "az-zalzala", "al-adiyat", "al-qaria", "at-takathur", "al-asr", "al-humaza", "al-fil", "quraysh", "al-maun", "al-kawthar", "al-kafirun", "an-nasr", "al-masad", "al-ikhlas", "al-falaq", "an-nas"];
export function tafsirAyahURL(bookId: number, surah: number, ayah: number): string | null {
  if (!VERIFIED_TAFSIR_BOOKS.has(bookId) || !verseURL(surah, ayah) || TAFSIR_SURAH_SLUGS.length !== AYAH_COUNTS.length) return null;
  return `https://quranpedia.net/tafsir/${TAFSIR_SURAH_SLUGS[surah - 1]}/${ayah}?book=${bookId}`;
}
export function tafsirPageURL(bookId: number, part: string, page: number | null): string | null {
  const partNumber = Number(String(part).trim());
  if (!VERIFIED_TAFSIR_BOOKS.has(bookId) || page == null || !Number.isInteger(page) || page < 1 || !Number.isInteger(partNumber) || partNumber < 1) return null;
  return `https://quranpedia.net/book/${bookId}/${partNumber}/${page}`;
}
// حدود المقاطع من صفحات إبراهيم الرسمية التي فُحصت: dorar.net/tafseer/14/1 إلى /14/12.
// بيانات إحالة فقط؛ لا نصوص تفسير ولا تخمين لنمط مقاطع السور الأخرى.
export function dorarPassage(surah: number, ayah: number): {firstAyah: number; lastAyah: number; url: string} | null {
  if (surah !== 14 || !verseURL(surah, ayah)) return null;
  const ends = [3, 8, 12, 18, 21, 23, 27, 31, 34, 41, 46, 52];
  const index = ends.findIndex(end => ayah <= end);
  if (index < 0) return null;
  return {firstAyah: index === 0 ? 1 : ends[index - 1] + 1, lastAyah: ends[index], url: `https://dorar.net/tafseer/14/${index + 1}`};
}

// قائمة «المصادر» في «عن سِياق»: ما تستخدمه النتائج فعلًا فقط، بدوره ورابطه العام.
// كتاب التفسير لا يدخل إلا إذا كانت بياناته محمّلة، ونمط رابطه مفحوصًا، وشرطه في المرجعية مثبتًا (source-policy.json).
// الدرر السنية لا تُدرج مصدرًا للبيانات قبل ربط نصوصها؛ الإحالة الخارجية إلى مقطع مفحوص فقط.
export type AboutSource = {title: string; role: string; url: string; tafsirBookId: number | null};
export const ABOUT_SOURCES: AboutSource[] = [
  {title: "الموسوعة القرآنية", role: "النص القرآني (مصحف حفص) والآيات المحيطة به، وتُقرأ منها نصوص كتابي التفسير.", url: "https://quranpedia.net/", tafsirBookId: null},
  {title: "تفسير مجاهد", role: "نص التفسير الأصلي حيث يتوفر · مجاهد بن جبر (ت ١٠٤هـ).", url: "https://quranpedia.net/book/269", tafsirBookId: 269},
  {title: "تفسير سفيان الثوري", role: "نص التفسير الأصلي حيث يتوفر · سفيان الثوري (ت ١٦١هـ).", url: "https://quranpedia.net/book/27758", tafsirBookId: 27758},
];
export const ABOUT_SOURCES_NOTE = "كتابا التفسير من مصادر القرون الثلاثة الأولى التي تقبلها المرجعية المعتمدة، ويغطيان بعض الآيات فقط؛ يظهر غياب التفسير صراحة ولا نعرض تفسير آية أخرى. داخل النتيجة يفتح كل رابط الآية نفسها أو صفحة التفسير نفسها.";
export const DORAR_NOTE = "الدرر السنية (التفسير) منصة معتمدة في المرجعية، لكن نصوصها لم تُربط بسِياق بعد؛ لذلك لا نعرض نصًا منها. عند غياب تفسير محفوظ نُحيل إلى مقطع الآيات إذا تحققنا من رابطه، ولا نضع رابطًا عامًا بدل الموضع المحدد.";
