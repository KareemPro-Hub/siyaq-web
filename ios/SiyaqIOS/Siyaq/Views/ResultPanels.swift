import SwiftUI

/// النص الأصلي كما ورد، منفصلًا عن اقتباس المستخدم.
struct TextPanel: View {
    let result: ReviewResult
    let candidate: Candidate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "اقتباسك كما كتبته")
                Text(result.quote)
                    .siyaqFont(.body)
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(Palette.line).frame(height: 1)

            Kicker(text: candidate.verses.count > 1 ? "الآيات كاملة كما وردت في المصدر" : "الآية كاملة كما وردت في المصدر")

            ForEach(candidate.verses) { verse in
                VStack(alignment: .leading, spacing: 6) {
                    if candidate.verses.count > 1 {
                        Text(ArabicFormat.location(of: verse))
                            .siyaqFont(.small)
                            .foregroundStyle(Palette.muted)
                    }
                    QuranText(text: verse.text, style: .quran)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(candidate.verses) { verse in
                    VerseSourceLink(verse: verse, showsLocation: candidate.verses.count > 1)
                }
            }
            .padding(.top, 4)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
    }
}

/// رابط الآية نفسها في مصدرها (مصحف حفص بالموسوعة القرآنية)، لا الصفحة الرئيسية.
struct VerseSourceLink: View {
    let verse: Verse
    var showsLocation = false

    var body: some View {
        let title = showsLocation ? "افتح \(ArabicFormat.location(of: verse)) في مصدرها" : "افتح الآية في مصدرها"
        if let url = SourceLinks.verse(surah: verse.surah, ayah: verse.ayah) {
            SourceLinkRow(title: title, url: url)
        } else {
            Text("رابط هذه الآية غير متاح؛ رقمها لا يطابق مصحف حفص.")
                .siyaqFont(.small)
                .foregroundStyle(Palette.muted)
        }
    }
}

/// الآية وما يحيط بها داخل السورة نفسها.
struct ContextPanel: View {
    let result: ReviewResult
    let candidate: Candidate

    private var matchedIDs: Set<String> { Set(candidate.verses.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "الآية وما يحيط بها")
            if result.context.isEmpty {
                Text("لا يتوفر سياق لهذه النتيجة في بيانات الخدمة.")
                    .siyaqFont(.body)
                    .foregroundStyle(Palette.muted)
            } else {
                ForEach(result.context) { verse in
                    let isMatch = matchedIDs.contains(verse.id)
                    VStack(alignment: .leading, spacing: 6) {
                        AdaptiveRow(spacing: 6) {
                            Text(ArabicFormat.location(of: verse))
                                .siyaqFont(.small)
                                .foregroundStyle(Palette.muted)
                            if isMatch {
                                Text("موضع الاقتباس")
                                    .siyaqFont(.small)
                                    .foregroundStyle(Palette.navy)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Tone.mint.background))
                            }
                        }
                        QuranText(text: verse.text, style: .quranContext)
                    }
                    .padding(isMatch ? 12 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isMatch ? Palette.highlight : Color.clear)
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// التفسير المتاح: اسم الكتاب والمؤلف والموضع والرابط. كلام المفسر منفصل عن النص القرآني.
/// لكل آية محددة: نص تفسيرها إن وُجد، أو سبب غيابه بصدق — دون عرض تفسير آية أخرى.
struct TafsirPanel: View {
    let result: ReviewResult
    let candidate: Candidate

    private var summary: ResultSourceSummary { ResultSourceSummary(result: result, candidate: candidate) }

    var body: some View {
        let summary = self.summary
        let multiple = candidate.verses.count > 1
        VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "نص التفسير ومصدره")
            if !summary.tafsir.isEmpty {
                Text("ما يلي كلام المفسرين منقولًا من كتبهم، وليس نصًا قرآنيًا.")
                    .siyaqFont(.small)
                    .foregroundStyle(Palette.muted)
            }
            ForEach(candidate.verses) { verse in
                let entries = result.tafsir.first(where: { $0.verseId == verse.id })?.entries ?? []
                VStack(alignment: .leading, spacing: 14) {
                    if multiple {
                        Text("تفسير \(ArabicFormat.location(of: verse))")
                            .siyaqFont(.captionBold)
                            .foregroundStyle(Palette.navy)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if entries.isEmpty {
                        MissingTafsirNote(verse: verse, reason: summary.missingTafsirReason)
                    } else {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            TafsirEntryView(entry: entry, verse: verse)
                            if index < entries.count - 1 {
                                Rectangle().fill(Palette.line).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// غياب التفسير لآية بعينها: إحالة إلى مقطع موثق فقط، بلا رابط عام بديل عن الموضع.
struct MissingTafsirNote: View {
    let verse: Verse
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reason)
                .siyaqFont(.body)
                .foregroundStyle(Palette.navy)
                .fixedSize(horizontal: false, vertical: true)
            if let passage = SourceLinks.dorarPassage(surah: verse.surah, ayah: verse.ayah) {
                SourceLinkRow(title: "تفسير سورة \(verse.surahName)، الآيات \(ArabicFormat.number(passage.firstAyah))–\(ArabicFormat.number(passage.lastAyah)) في الدرر السنية", url: passage.url)
                    .accessibilityIdentifier("dorarTafsirPassage")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct TafsirEntryView: View {
    let entry: TafsirEntry
    let verse: Verse
    @State private var expanded = false

    private var isLong: Bool { entry.text.count > 600 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.bookName.isEmpty ? "كتاب غير مسمى" : entry.bookName)
                .siyaqFont(.bodyBold)
                .foregroundStyle(Palette.navy)
                .accessibilityAddTraits(.isHeader)
            let reference = ArabicFormat.reference(part: entry.part, page: entry.page)
            Text([entry.author, reference].filter { !$0.isEmpty }.joined(separator: " · "))
                .siyaqFont(.small)
                .foregroundStyle(Palette.muted)
            Text(entry.text)
                .siyaqFont(.body)
                .foregroundStyle(Palette.navy)
                .lineSpacing(7)
                .lineLimit(expanded || !isLong ? nil : 10)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if isLong {
                Button(expanded ? "اختصر النص" : "اقرأ نص التفسير كاملًا") {
                    expanded.toggle()
                }
                .siyaqFont(.captionBold)
                .foregroundStyle(Palette.tealDark)
                .frame(minHeight: 44)
            }
            if let url = SourceLinks.tafsirAyah(bookId: entry.bookId, surah: verse.surah, ayah: verse.ayah) {
                SourceLinkRow(title: "افتح التفسير في مصدره", url: url)
            } else {
                Text("رابط موضع هذا التفسير غير متاح؛ لم يُفحص نمط صفحات هذا الكتاب.")
                    .siyaqFont(.small)
                    .foregroundStyle(Palette.muted)
            }
        }
    }
}

/// بطاقة «المصدر»: موضع الآية ومصدر نصها، ثم كتاب التفسير ومرجعه، ثم نسخ البيانات المعلنة.
/// كل رابط يفتح الموضع نفسه، لا الصفحة الرئيسية.
struct SourcePanel: View {
    let result: ReviewResult
    let candidate: Candidate
    let origin: ResultOrigin
    let savedAt: Date?

    var body: some View {
        let summary = ResultSourceSummary(result: result, candidate: candidate)
        VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "النص القرآني")
            ForEach(Array(summary.verses.enumerated()), id: \.offset) { _, verse in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verse.location)
                        .siyaqFont(.bodyBold)
                        .foregroundStyle(Palette.navy)
                    Text("مصدر النص: \(summary.quranSourceName) — مصحف حفص")
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.muted)
                    if let url = verse.url {
                        SourceLinkRow(title: "افتح الآية في مصدرها", url: url)
                    }
                }
            }

            Rectangle().fill(Palette.line).frame(height: 1)

            Kicker(text: "التفسير")
            ForEach(Array(summary.tafsir.enumerated()), id: \.offset) { _, link in
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.bookName)
                        .siyaqFont(.bodyBold)
                        .foregroundStyle(Palette.navy)
                    Text([link.author, link.reference, summary.verses.count > 1 ? verseNumber(link.verseId, in: summary) : ""]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.muted)
                    if let url = link.url {
                        SourceLinkRow(title: "افتح التفسير في مصدره", url: url)
                    } else {
                        Text("رابط موضع هذا التفسير غير متاح.")
                            .siyaqFont(.small)
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            if !summary.versesWithoutTafsir.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if summary.verses.count > 1 {
                        Text("بلا تفسير محفوظ: " + summary.versesWithoutTafsir.map(\.location).joined(separator: "، "))
                            .siyaqFont(.caption)
                            .foregroundStyle(Palette.navy)
                    }
                    Text(summary.missingTafsirReason)
                        .siyaqFont(.caption)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rectangle().fill(Palette.line).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                infoRow("نسخة النص القرآني", summary.quranVersion.isEmpty ? "لم تعلنها الخدمة" : summary.quranVersion)
                ForEach(Array(summary.tafsirVersions.enumerated()), id: \.offset) { _, book in
                    infoRow("نسخة \(book.name)", book.version)
                }
                if origin != .live {
                    infoRow("نوع النتيجة", "مثال معاينة مسجل")
                }
                if let savedAt {
                    infoRow("تاريخ الحفظ", ArabicFormat.date(savedAt))
                }
            }
        }
    }

    private func verseNumber(_ id: String, in summary: ResultSourceSummary) -> String {
        summary.verses.first(where: { $0.verseId == id }).map { "الآية \(ArabicFormat.number($0.ayah))" } ?? ""
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        AdaptiveRow(spacing: 6) {
            Text(label + ":")
                .siyaqFont(.small)
                .foregroundStyle(Palette.muted)
            Text(value)
                .siyaqFont(.caption)
                .foregroundStyle(Palette.navy)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// عرض النص القرآني كما هو دون أي تعديل.
struct QuranText: View {
    let text: String
    let style: SiyaqTextStyle

    var body: some View {
        Text(verbatim: text)
            .siyaqFont(style)
            .foregroundStyle(Palette.navy)
            .lineSpacing(10)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
