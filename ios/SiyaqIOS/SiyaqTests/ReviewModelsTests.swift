import XCTest
@testable import Siyaq

/// فك كل أمثلة الخدمة الفعلية والتعامل مع null والقيم غير المعروفة.
final class ReviewModelsTests: XCTestCase {

    func testAllServiceSamplesDecode() throws {
        for name in Samples.files {
            XCTAssertNoThrow(try Samples.result(name), "فشل فك \(name)")
        }
    }

    func testPartialMatchWithTafsir() throws {
        let result = try Samples.result("01-partial")
        XCTAssertEqual(result.status, .matched)
        XCTAssertEqual(result.selected?.id, "4:43")
        XCTAssertEqual(result.selected?.kind, .partial)
        XCTAssertEqual(result.context.map(\.id), ["4:42", "4:43", "4:44"])
        XCTAssertEqual(result.tafsir.first?.verseId, "4:43")
        let entries = try XCTUnwrap(result.tafsir.first?.entries)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].bookName, "تفسير مجاهد")
        XCTAssertEqual(entries[0].part, "1")
        XCTAssertEqual(entries[0].page, 276)
        XCTAssertEqual(entries[2].bookId, 27758)
        XCTAssertEqual(result.sourceVersion, "2026-10-01")
        XCTAssertTrue(result.isDisplayableMatch)
    }

    func testChoicesListIsLimitedButCountIsTotal() throws {
        let result = try Samples.result("02-choices")
        XCTAssertEqual(result.status, .choices)
        XCTAssertNil(result.selected)
        XCTAssertEqual(result.candidates.count, 12)
        XCTAssertEqual(result.candidateCount, 42)
        XCTAssertEqual(result.hiddenCandidateCount, 30)
        XCTAssertTrue(result.context.isEmpty)
        XCTAssertTrue(result.tafsir.isEmpty)
        XCTAssertFalse(result.isDisplayableMatch)
    }

    func testPossibleIsNotAutoSelected() throws {
        let result = try Samples.result("03-possible")
        XCTAssertEqual(result.status, .possible)
        XCTAssertNil(result.selected)
        XCTAssertEqual(result.candidates.first?.kind, .possible)
        XCTAssertFalse(result.isDisplayableMatch)
    }

    func testNotFound() throws {
        let result = try Samples.result("04-not-found")
        XCTAssertEqual(result.status, .notFound)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.candidateCount, 0)
        XCTAssertNil(result.selected)
    }

    func testFullMatchWithEmptyTafsirEntries() throws {
        let result = try Samples.result("05-full-no-tafsir")
        XCTAssertEqual(result.selected?.kind, .full)
        XCTAssertEqual(result.tafsir.count, 1)
        XCTAssertTrue(result.tafsir[0].entries.isEmpty)
        XCTAssertTrue(result.tafsirWithEntries.isEmpty)
    }

    func testSelectedPossibleKeepsWarningAndDifferences() throws {
        let result = try Samples.result("06-selected-possible")
        XCTAssertEqual(result.status, .matched)
        XCTAssertEqual(result.selected?.kind, .possible)
        XCTAssertTrue(result.isSelectedPossible)
        XCTAssertEqual(result.differences.count, 6)
        XCTAssertEqual(result.differences[2], Difference(text: "الصلاه", type: .input))
        XCTAssertEqual(result.differences[3], Difference(text: "الصلاة", type: .source))
    }

    /// النص القرآني يبقى كما ورد حرفًا حرفًا، بما في ذلك محرف BOM (U+FEFF) في بداية بعض الآيات من المصدر.
    /// تصحيح مراجعة Codex: JSONSerialization على Apple يحذف U+FEFF (٤٢١ مقابل ٤٢٢)، فلا يصلح مرجعًا حرفيًا.
    /// المرجع هنا بايتات ملف المثال الخام نفسه، دون أي فك وسيط.
    func testVerseTextIsKeptVerbatim() throws {
        let data = try Samples.data("01-partial")
        let decoded = try Samples.result("01-partial")
        let text = try XCTUnwrap(decoded.selected?.verses.first?.text)

        // ١) المحرف الأول BOM كما في المصدر، وعدد المحارف كاملًا.
        XCTAssertEqual(text.unicodeScalars.first, Unicode.Scalar(0xFEFF))
        XCTAssertEqual(text.unicodeScalars.count, 422)

        // ٢) بايتات UTF-8 للنص المفكوك موجودة حرفيًا داخل ملف JSON الخام (الملف بلا تهريب \u).
        XCTAssertNil(data.range(of: Data("\\u".utf8)), "المثال يجب ألا يحتوي تهريب \\u حتى يصلح مرجعًا بالبايت")
        let needle = Data(("\"" + text + "\"").utf8)
        XCTAssertNotNil(data.range(of: needle), "النص المفكوك يجب أن يطابق بايتات المصدر حرفيًا")

        // ٣) encode/decode ذهابًا وإيابًا دون فقد أي محرف.
        let again = try JSONDecoder().decode(ReviewResult.self, from: JSONEncoder().encode(decoded))
        let roundTripped = try XCTUnwrap(again.selected?.verses.first?.text)
        XCTAssertEqual(Array(roundTripped.unicodeScalars), Array(text.unicodeScalars))
        for (a, b) in zip(again.context, decoded.context) {
            XCTAssertEqual(Array(a.text.unicodeScalars), Array(b.text.unicodeScalars))
        }
    }

    func testNullsAndMissingOptionalFields() throws {
        let json = """
        {"status":"matched","quote":"قل هو الله أحد","candidates":null,"selected":{"id":"112:1","kind":"full","verses":[{"id":"112:1","surah":112,"surahName":"الإخلاص","ayah":1,"text":"قُلْ هُوَ اللَّهُ أَحَدٌ"}],"note":null},
         "context":null,"tafsir":[{"verseId":"112:1","entries":[{"bookId":1,"bookName":"كتاب","author":"مؤلف","part":"ج","page":null,"text":"نص","url":"https://quranpedia.net/"}]}],
         "differences":null,"sourceVersion":null,"aiExplanation":"حقل جديد يجب تجاهله"}
        """
        let result = try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8))
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.candidateCount, 0)
        XCTAssertEqual(result.selected?.note, "")
        XCTAssertTrue(result.context.isEmpty)
        XCTAssertTrue(result.differences.isEmpty)
        XCTAssertEqual(result.sourceVersion, "")
        let entry = try XCTUnwrap(result.tafsir.first?.entries.first)
        XCTAssertNil(entry.page)
        XCTAssertEqual(entry.part, "ج")
    }

    func testUnknownEnumValuesDoNotFailAndRoundTrip() throws {
        let json = """
        {"status":"future_status","quote":"أ ب","candidates":[{"id":"x","kind":"new_kind","verses":[],"note":""}],"candidateCount":1,"selected":null,"context":[],"tafsir":[],"differences":[{"text":"ت","type":"other"}],"sourceVersion":"v"}
        """
        let result = try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.status, .unknown("future_status"))
        XCTAssertEqual(result.candidates.first?.kind, .unknown("new_kind"))
        XCTAssertEqual(result.differences.first?.type, .unknown("other"))

        let again = try JSONDecoder().decode(ReviewResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(again, result)
    }

    func testNumericPartIsTolerated() throws {
        let json = """
        {"bookId":3,"bookName":"ب","author":"م","part":2,"page":15,"text":"ن","url":"https://quranpedia.net/"}
        """
        let entry = try JSONDecoder().decode(TafsirEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.part, "2")
    }

    func testMissingVerseTextFails() {
        let json = """
        {"status":"matched","quote":"أ ب","candidates":[],"candidateCount":0,"selected":{"id":"1:1","kind":"full","verses":[{"id":"1:1","surah":1,"surahName":"الفاتحة","ayah":1}],"note":""},"context":[],"tafsir":[],"differences":[],"sourceVersion":"v"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8)))
    }

    func testLocationFormatting() throws {
        let a = Verse(id: "4:43", surah: 4, surahName: "النساء", ayah: 43, text: "")
        let b = Verse(id: "4:44", surah: 4, surahName: "النساء", ayah: 44, text: "")
        XCTAssertEqual(ArabicFormat.location(of: a), "سورة النساء · الآية ٤٣")
        XCTAssertEqual(ArabicFormat.location(of: [a, b]), "سورة النساء · الآيات ٤٣–٤٤")
        XCTAssertEqual(ArabicFormat.reference(part: "1", page: 276), "ج١، ص٢٧٦")
        XCTAssertEqual(ArabicFormat.reference(part: "", page: nil), "")
    }

    func testShareTextKeepsOriginalTextAndWarnsForPossible() throws {
        let result = try Samples.result("06-selected-possible")
        let candidate = try XCTUnwrap(result.selected)
        let text = ShareText.make(result: result, candidate: candidate)
        XCTAssertTrue(text.hasPrefix(candidate.verses[0].text))
        XCTAssertTrue(text.contains("سورة النساء · الآية ٤٣"))
        XCTAssertTrue(text.contains("تشابه الألفاظ"))
        XCTAssertTrue(text.contains("https://quranpedia.net/"))
        XCTAssertTrue(text.contains("2026-10-01"))
    }
}
