import XCTest
@testable import Siyaq

/// روابط المصدر وبطاقة المصدر ورسائل البحث (طلبات كريم ٣ أكتوبر).
final class SourceAndSearchTests: XCTestCase {

    private func verse(_ surah: Int, _ ayah: Int, name: String = "النساء") -> Verse {
        Verse(id: "\(surah):\(ayah)", surah: surah, surahName: name, ayah: ayah, text: "نص \(surah):\(ayah)")
    }

    private func entry(book: Int = 269, part: String = "1", page: Int? = 276, text: String = "قول المفسر") -> TafsirEntry {
        TafsirEntry(bookId: book, bookName: book == 269 ? "تفسير مجاهد" : "تفسير سفيان الثوري",
                    author: book == 269 ? "مجاهد بن جبر" : "سفيان الثوري",
                    part: part, page: page, text: text, url: "https://quranpedia.net/book/\(book)")
    }

    private func result(candidate: Candidate, tafsir: [TafsirGroup], sources: ResultSources? = nil,
                        search: ReviewSearchInfo? = nil) -> ReviewResult {
        ReviewResult(status: .matched, quote: "q", candidates: [candidate], candidateCount: 1, selected: candidate,
                     context: candidate.verses, tafsir: tafsir, differences: [], sourceVersion: "v-old",
                     sources: sources, search: search)
    }

    // MARK: روابط

    func testAyahCountsMatchHafs() {
        XCTAssertEqual(SourceLinks.ayahCounts.count, 114)
        XCTAssertEqual(SourceLinks.ayahCounts.reduce(0, +), 6236)
    }

    func testVerseLinkOpensTheAyahItselfAndRejectsImpossibleAyahs() {
        XCTAssertEqual(SourceLinks.verse(surah: 4, ayah: 43)?.absoluteString, "https://quranpedia.net/surah/1/4/43")
        XCTAssertEqual(SourceLinks.verse(surah: 114, ayah: 6)?.absoluteString, "https://quranpedia.net/surah/1/114/6")
        XCTAssertNil(SourceLinks.verse(surah: 1, ayah: 8))
        XCTAssertNil(SourceLinks.verse(surah: 0, ayah: 1))
        XCTAssertNil(SourceLinks.verse(surah: 115, ayah: 1))
        XCTAssertNil(SourceLinks.verse(surah: 2, ayah: 0))
    }

    func testTafsirLinkOpensThePrintedPageOnlyForVerifiedBooks() {
        XCTAssertEqual(SourceLinks.tafsirPage(bookId: 269, part: "1", page: 276)?.absoluteString,
                       "https://quranpedia.net/book/269/1/276")
        XCTAssertEqual(SourceLinks.tafsirPage(bookId: 27758, part: " 1 ", page: 214)?.absoluteString,
                       "https://quranpedia.net/book/27758/1/214")
        XCTAssertNil(SourceLinks.tafsirPage(bookId: 269, part: "1", page: nil), "لا صفحة ⇒ لا رابط بديل عام")
        XCTAssertNil(SourceLinks.tafsirPage(bookId: 269, part: "المقدمة", page: 3))
        XCTAssertNil(SourceLinks.tafsirPage(bookId: 999, part: "1", page: 3), "كتاب لم يُفحص نمطه")
    }

    func testTafsirLinksSelectTheAyahAndBookRatherThanTheWholePrintedPage() {
        XCTAssertEqual(SourceLinks.tafsirSurahSlugs.count, 114)
        XCTAssertEqual(Set(SourceLinks.tafsirSurahSlugs).count, 114)
        XCTAssertEqual(SourceLinks.tafsirAyah(bookId: 269, surah: 14, ayah: 43)?.absoluteString,
                       "https://quranpedia.net/tafsir/ibrahim/43?book=269")
        XCTAssertEqual(SourceLinks.tafsirAyah(bookId: 27758, surah: 14, ayah: 43)?.absoluteString,
                       "https://quranpedia.net/tafsir/ibrahim/43?book=27758")
        XCTAssertEqual(SourceLinks.tafsirAyah(bookId: 269, surah: 1, ayah: 1)?.absoluteString,
                       "https://quranpedia.net/tafsir/al-fatiha/1?book=269")
        XCTAssertEqual(SourceLinks.tafsirAyah(bookId: 269, surah: 114, ayah: 6)?.absoluteString,
                       "https://quranpedia.net/tafsir/an-nas/6?book=269")
        XCTAssertNil(SourceLinks.tafsirAyah(bookId: 999, surah: 14, ayah: 43))
        XCTAssertNil(SourceLinks.tafsirAyah(bookId: 269, surah: 14, ayah: 53))
        XCTAssertNil(SourceLinks.tafsirAyah(bookId: 269, surah: 0, ayah: 1))
    }

    func testDorarIbrahimPassagesOpenTheContainingPassageWithoutGuessingOtherSurahs() throws {
        let passage = try XCTUnwrap(SourceLinks.dorarPassage(surah: 14, ayah: 42))
        XCTAssertEqual(passage.url.absoluteString, "https://dorar.net/tafseer/14/11")
        XCTAssertEqual(passage.firstAyah, 42)
        XCTAssertEqual(passage.lastAyah, 46)
        XCTAssertEqual(SourceLinks.dorarPassage(surah: 14, ayah: 43), passage)
        XCTAssertEqual(SourceLinks.dorarPassage(surah: 14, ayah: 41)?.url.lastPathComponent, "10")
        XCTAssertEqual(SourceLinks.dorarPassage(surah: 14, ayah: 47)?.url.lastPathComponent, "12")
        for ayah in 1...52 {
            let location = try XCTUnwrap(SourceLinks.dorarPassage(surah: 14, ayah: ayah))
            XCTAssertTrue((location.firstAyah...location.lastAyah).contains(ayah))
        }
        XCTAssertNil(SourceLinks.dorarPassage(surah: 14, ayah: 53))
        XCTAssertNil(SourceLinks.dorarPassage(surah: 14, ayah: 0))
        XCTAssertNil(SourceLinks.dorarPassage(surah: 4, ayah: 43))
    }

    // MARK: بطاقة المصدر

    func testSummaryLinksOnlySelectedVersesAndDeduplicatesTafsir() {
        let candidate = Candidate(id: "4:43", kind: .full, verses: [verse(4, 43)], note: "")
        let groups = [
            TafsirGroup(verseId: "4:43", entries: [entry(), entry(), entry(book: 27758, page: 98)]),
        ]
        let sources = ResultSources(
            quran: .init(name: "الموسوعة القرآنية", version: "2026-10-01"),
            tafsir: [.init(bookId: 269, name: "تفسير مجاهد", author: "مجاهد بن جبر", version: "2026-08-10"),
                     .init(bookId: 27758, name: "تفسير سفيان الثوري", author: "سفيان الثوري", version: "2026-08-10")]
        )
        let summary = ResultSourceSummary(result: result(candidate: candidate, tafsir: groups, sources: sources),
                                          candidate: candidate)
        XCTAssertEqual(summary.verses.map(\.url?.absoluteString), ["https://quranpedia.net/surah/1/4/43"])
        XCTAssertEqual(summary.quranVersion, "2026-10-01", "النسخة المعلنة تتقدم على sourceVersion")
        XCTAssertEqual(summary.tafsir.count, 2, "لا تكرار للموضع نفسه")
        XCTAssertEqual(summary.tafsir.first?.url?.absoluteString, "https://quranpedia.net/tafsir/an-nisa/43?book=269")
        XCTAssertTrue(summary.versesWithoutTafsir.isEmpty)
        XCTAssertEqual(summary.tafsirVersions.map(\.version), ["2026-08-10", "2026-08-10"])
    }

    func testMissingTafsirIsReportedPerVerseWithoutBorrowingAnotherVerse() {
        let candidate = Candidate(id: "2:255", kind: .full, verses: [verse(2, 255, name: "البقرة"), verse(2, 256, name: "البقرة")], note: "")
        let groups = [
            TafsirGroup(verseId: "2:255", entries: []),
            TafsirGroup(verseId: "2:256", entries: [entry(page: 120)]),
        ]
        let sources = ResultSources(quran: nil, tafsir: [.init(bookId: 269, name: "تفسير مجاهد", author: "مجاهد بن جبر", version: "2026-08-10")])
        let summary = ResultSourceSummary(result: result(candidate: candidate, tafsir: groups, sources: sources),
                                          candidate: candidate)
        XCTAssertEqual(summary.versesWithoutTafsir.map(\.verseId), ["2:255"])
        XCTAssertEqual(summary.tafsir.map(\.verseId), ["2:256"])
        XCTAssertTrue(summary.missingTafsirReason.contains("تفسير مجاهد"))
        XCTAssertTrue(summary.missingTafsirReason.contains("لم نعرض تفسير آية أخرى"))
        XCTAssertEqual(summary.quranVersion, "v-old", "بلا نسخة معلنة نعرض sourceVersion كما هو")
        XCTAssertEqual(summary.quranSourceName, "الموسوعة القرآنية")
    }

    // MARK: فك الحقول الجديدة

    func testDecodesSourcesAndSearchAndToleratesOldOrBrokenShapes() throws {
        let json = """
        {"status":"possible","quote":"q","candidates":[{"id":"4:43","kind":"possible","verses":[{"id":"4:43","surah":4,"surahName":"النساء","ayah":43,"text":"t"}],"note":""}],
         "candidateCount":1,"selected":null,"context":[],"tafsir":[],"differences":[],"sourceVersion":"v",
         "search":{"query":"لا تقربوا الصلاة","ignored":["«قال تعالى»","Ne/a",""],"method":"segments"},
         "sources":{"quran":{"name":"الموسوعة القرآنية","version":"2026-10-01"},"tafsir":[{"bookId":269,"name":"تفسير مجاهد","author":"مجاهد","version":"2026-08-10"}]}}
        """
        let decoded = try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.search?.method, "segments")
        XCTAssertEqual(decoded.search?.ignored, ["«قال تعالى»", "Ne/a"])
        XCTAssertEqual(decoded.sources?.quran?.version, "2026-10-01")
        // الحفظ ثم الاسترجاع يحتفظ بالحقول.
        let roundTrip = try JSONDecoder().decode(ReviewResult.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)

        let old = """
        {"status":"not_found","quote":"q","candidates":[],"candidateCount":0,"selected":null,"context":[],"tafsir":[],"differences":[],"sourceVersion":"v"}
        """
        let legacy = try JSONDecoder().decode(ReviewResult.self, from: Data(old.utf8))
        XCTAssertNil(legacy.search)
        XCTAssertNil(legacy.sources)

        let broken = """
        {"status":"not_found","quote":"q","candidates":[],"sourceVersion":"v","search":"x","sources":7}
        """
        let tolerant = try JSONDecoder().decode(ReviewResult.self, from: Data(broken.utf8))
        XCTAssertNil(tolerant.search, "صيغة غير متوقعة لا تُسقط النتيجة")
        XCTAssertNil(tolerant.sources)
    }

    // MARK: رسائل البحث

    func testNotFoundDistinguishesImageReadingFromTypedText() {
        let typed = ReviewSearchNotice.notFound(fromImage: false)
        let image = ReviewSearchNotice.notFound(fromImage: true)
        XCTAssertNotEqual(typed, image)
        XCTAssertTrue(image.message.contains("قد توجد أخطاء في قراءة الصورة"))
        XCTAssertTrue(image.message.contains("لم نصحح النص تلقائيًا"))
        XCTAssertFalse(typed.message.contains("الصورة"))
        // انقطاع الخدمة رسالة مستقلة من ReviewError، لا «لم نجد».
        for outage in [ReviewError.offline, .unreachable, .timedOut, .invalidResponse] {
            XCTAssertFalse(outage.message.contains("لم نعثر"))
            XCTAssertFalse(outage.message.contains("قراءة الصورة"))
        }
    }

    func testPossibleBySegmentsIsNeverPresentedAsConfirmed() {
        let segments = ReviewSearchInfo(query: "q", ignored: [], method: "segments")
        let message = ReviewSearchNotice.possible(search: segments, fromImage: true)
        XCTAssertEqual(message.title, "تشابه محتمل، وليس إثباتًا")
        XCTAssertTrue(message.message.contains("لن يُعد مطابقة مؤكدة"))
        XCTAssertTrue(message.message.contains("قراءة الصورة"))
        let similar = ReviewSearchNotice.possible(search: nil, fromImage: false)
        XCTAssertTrue(similar.message.contains("ليس") || similar.message.contains("مؤكدة"))
    }

    func testIgnoredNoteListsWhatWasDroppedFromTheSearchCopyOnly() {
        XCTAssertNil(ReviewSearchNotice.ignored(nil))
        XCTAssertNil(ReviewSearchNotice.ignored(ReviewSearchInfo(query: "q", ignored: [], method: "exact")))
        let note = ReviewSearchNotice.ignored(ReviewSearchInfo(query: "q", ignored: ["«قال تعالى»", "Ne/a"], method: "exact"))
        XCTAssertEqual(note, "تجاهل البحث ما ليس من نص الآية: «قال تعالى»، Ne/a. نصك المعروض لم يتغير.")
        XCTAssertTrue(ReviewSearchNotice.looksLikeImageText(ReviewSearchInfo(query: "q", ignored: ["«قال تعالى»", "Ne/a"], method: "segments")))
        XCTAssertFalse(ReviewSearchNotice.looksLikeImageText(ReviewSearchInfo(query: "q", ignored: ["«قال تعالى»"], method: "exact")))
        XCTAssertFalse(ReviewSearchNotice.looksLikeImageText(nil))
    }

    // MARK: أصل النص في الجلسة

    @MainActor
    func testSessionRemembersThatTheQuoteCameFromAnImageUntilCleared() async {
        let session = ReviewSession()
        XCTAssertFalse(session.inputFromImage)
        session.useExtractedText("قال تعالى لا تقربوا الصلاة")
        XCTAssertTrue(session.inputFromImage)
        session.editInput("لا تقربوا الصلاة")
        XCTAssertTrue(session.inputFromImage, "مراجعة نص الصورة وتصحيحه لا يلغي أصله")
        session.editInput("   ")
        XCTAssertFalse(session.inputFromImage)
        session.useExtractedText("نص")
        session.useSample("قل هو الله أحد")
        XCTAssertFalse(session.inputFromImage)
        XCTAssertEqual(session.input, "قل هو الله أحد")
    }

    // MARK: «المصادر» في «عن سِياق»

    func testAboutSourcesListOnlyWhatResultsActuallyUse() throws {
        let entries = AboutSources.entries
        XCTAssertEqual(entries.first?.title, "الموسوعة القرآنية")
        XCTAssertEqual(entries.first?.url.absoluteString, "https://quranpedia.net/")
        // كتب التفسير في القائمة هي نفسها الكتب المحمّلة المفحوصة روابطها، لا أكثر ولا أقل.
        XCTAssertEqual(Set(entries.compactMap(\.tafsirBookId)), SourceLinks.verifiedTafsirBooks)
        for entry in entries {
            XCTAssertEqual(entry.url.scheme, "https")
            XCTAssertEqual(entry.url.host, "quranpedia.net", "لا مصدر بيانات من نطاق آخر قبل ربطه: \(entry.title)")
            XCTAssertFalse(entry.role.isEmpty)
            if let id = entry.tafsirBookId {
                XCTAssertEqual(entry.url.absoluteString, "https://quranpedia.net/book/\(id)")
            }
        }
        // لا حديث ولا فقه ولا الدرر مصدرًا للبيانات.
        let joined = entries.map { $0.title + $0.role + $0.url.absoluteString }.joined()
        for banned in ["حديث", "الفقه", "dorar", "shamela", "الدرر"] {
            XCTAssertFalse(joined.contains(banned), banned)
        }
        XCTAssertTrue(AboutSources.dorarNote.contains("لم تُربط"))
        // كل كتاب يظهر في أمثلة النتائج مذكور في القائمة.
        let listed = Set(entries.compactMap(\.tafsirBookId))
        for name in Samples.files {
            let result = try Samples.result(name)
            for group in result.tafsir {
                for entry in group.entries {
                    XCTAssertTrue(listed.contains(entry.bookId), "\(name): \(entry.bookId)")
                }
            }
        }
    }

    // MARK: سطر الإصدار

    func testVersionLineFollowsBundleVersionAndBuild() {
        XCTAssertEqual(AppVersionText.make(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"]),
                       "سِياق — الإصدار 0.1.0 (1)")
        XCTAssertEqual(AppVersionText.make(info: ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "7"]),
                       "سِياق — الإصدار 0.2.0 (7)")
        XCTAssertEqual(AppVersionText.make(info: nil), "سِياق — الإصدار — (—)")
        XCTAssertEqual(AppVersionText.make(info: ["CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": " "]),
                       "سِياق — الإصدار — (—)", "متغير غير موسَّع لا يُعرض")
    }

    /// الخطة تقرأ الأرقام من إعدادات البناء، لا من نص ثابت.
    func testInfoPlistsTakeVersionAndBuildFromBuildSettings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Info.plist", "Info.Release.plist"] {
            let url = root.appendingPathComponent("Siyaq").appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            XCTAssertTrue(text.contains("<string>$(MARKETING_VERSION)</string>"), name)
            XCTAssertTrue(text.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"), name)
        }
    }
}
