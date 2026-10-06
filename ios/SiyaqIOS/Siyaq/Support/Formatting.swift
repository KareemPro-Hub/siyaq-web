import Foundation

/// تنسيقات عربية للعرض فقط (أرقام عربية مشرقية، المواضع، التاريخ).
enum ArabicFormat {
    static let locale = Locale(identifier: "ar@numbers=arab")

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale).grouping(.never))
    }

    /// part نص قد يكون رقمًا؛ يُعرض كما هو إن لم يكن رقمًا.
    static func part(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed) { return number(value) }
        return trimmed
    }

    static func location(of verse: Verse) -> String {
        "سورة \(verse.surahName) · الآية \(number(verse.ayah))"
    }

    /// موضع آية أو آيات متجاورة.
    static func location(of verses: [Verse]) -> String {
        guard let first = verses.first else { return "" }
        if verses.count == 1 { return location(of: first) }
        let sameSurah = verses.allSatisfy { $0.surah == first.surah }
        if sameSurah {
            let ayahs = verses.map(\.ayah)
            let contiguous = zip(ayahs, ayahs.dropFirst()).allSatisfy { $1 == $0 + 1 }
            if contiguous, let last = ayahs.last {
                return "سورة \(first.surahName) · الآيات \(number(ayahs[0]))–\(number(last))"
            }
            return "سورة \(first.surahName) · الآيات " + ayahs.map(number).joined(separator: "، ")
        }
        return verses.map { location(of: $0) }.joined(separator: "؛ ")
    }

    /// مرجع التفسير: ج١، ص٢٧٦ — مع تجاهل ما لم يرد.
    static func reference(part: String, page: Int?) -> String {
        var pieces: [String] = []
        let partText = self.part(part)
        if !partText.isEmpty { pieces.append("ج\(partText)") }
        if let page { pieces.append("ص\(number(page))") }
        return pieces.joined(separator: "، ")
    }

    static func date(_ date: Date) -> String {
        date.formatted(
            .dateTime.day().month(.wide).year().hour().minute()
                .locale(Locale(identifier: "ar"))
        )
    }
}

/// نص المشاركة: النص الأصلي كما ورد + الموضع + المصدر + إصدار البيانات.
enum ShareText {
    static func make(result: ReviewResult, candidate: Candidate) -> String {
        var lines: [String] = candidate.verses.map(\.text)
        lines.append(ArabicFormat.location(of: candidate.verses))
        if candidate.kind == .possible {
            lines.append("تنبيه: هذا موضع محتمل بسبب تشابه الألفاظ، وليس مطابقة مؤكدة.")
        }
        // رابط الآية نفسها في مصدرها، لا الصفحة الرئيسية.
        let verseLinks = candidate.verses.compactMap { SourceLinks.verse(surah: $0.surah, ayah: $0.ayah)?.absoluteString }
        lines.append("مصدر النص: الموسوعة القرآنية — " + (verseLinks.isEmpty ? SafeLink.quranpedia.absoluteString : verseLinks.joined(separator: " ، ")))
        for book in tafsirBooks(in: result, verses: candidate.verses) {
            var line = "التفسير المنقول: \(book.name)"
            if !book.author.isEmpty { line += " — \(book.author)" }
            if let url = book.location { line += " — \(url.absoluteString)" }
            lines.append(line)
        }
        if !result.sourceVersion.isEmpty {
            lines.append("إصدار البيانات: \(result.sourceVersion)")
        }
        lines.append("عبر تطبيق سِياق")
        return lines.joined(separator: "\n")
    }

    /// كتب التفسير الفريدة في النتيجة (الاسم والمؤلف ورابط موضع أول نص معروض، دون نص التفسير).
    /// `verses`: الآيات المحددة؛ لا تُشارك كتب وردت لآية خارجها.
    static func tafsirBooks(in result: ReviewResult, verses: [Verse]? = nil) -> [(name: String, author: String, location: URL?)] {
        let allowed = verses.map { Set($0.map(\.id)) }
        var seen = Set<Int>()
        var books: [(name: String, author: String, location: URL?)] = []
        for group in result.tafsir where allowed?.contains(group.verseId) ?? true {
            let identity = group.verseId.split(separator: ":")
            guard identity.count == 2, let surah = Int(identity[0]), let ayah = Int(identity[1]) else { continue }
            for entry in group.entries {
                guard !entry.bookName.isEmpty, seen.insert(entry.bookId).inserted else { continue }
                books.append((entry.bookName, entry.author,
                              SourceLinks.tafsirAyah(bookId: entry.bookId, surah: surah, ayah: ayah)))
            }
        }
        return books
    }
}

/// سطر الإصدار في «عن سِياق»: الإصدار (MARKETING_VERSION) والبناء (CURRENT_PROJECT_VERSION) من Info.plist،
/// فلا يُكتب رقم ثابت في الكود ويتغير مع كل نسخة وبناء.
enum AppVersionText {
    static func make(info: [String: Any]?) -> String {
        "سِياق — الإصدار \(value(info?["CFBundleShortVersionString"])) (\(value(info?["CFBundleVersion"])))"
    }

    private static func value(_ raw: Any?) -> String {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.hasPrefix("$(") else { return "—" }
        return text
    }
}
