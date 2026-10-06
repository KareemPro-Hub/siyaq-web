import Foundation

/// فحص عقد العميل الحقيقي مع الخدمة المحلية فقط، وليس اختبار واجهة أو شرح AI.
@main struct LiveServiceCheck {
    static func main() async throws {
        let base = "http://127.0.0.1:3000"
        let service = LiveReviewService(endpoint: try ServiceEndpoint.reviewURL(from: base, allowLocalHTTP: true))
        struct Check: Encodable { let scenario: String; let status: String; let selected: String?; let candidates: Int; let originalTextKept: Bool }
        var checks: [Check] = []
        for (file, name) in [("01-partial", "matched"), ("02-choices", "choices"), ("04-not-found", "not_found")] {
            let sampleURL = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(file + ".json")
            let sample = try JSONDecoder().decode(ReviewResult.self, from: Data(contentsOf: sampleURL))
            let result = try await service.review(quote: sample.quote, selection: nil)
            guard result.status == sample.status else { throw CheckFailure.statusMismatch }
            let originalTextKept = result.selected == nil || Array(result.selected!.verses[0].text.unicodeScalars) == Array(sample.selected!.verses[0].text.unicodeScalars)
            guard originalTextKept else { throw CheckFailure.originalTextChanged }
            checks.append(Check(scenario: name, status: result.status.rawValue, selected: result.selected?.id, candidates: result.candidateCount, originalTextKept: originalTextKept))
            if result.status == .choices, let first = result.candidates.first {
                let selection = try await service.review(quote: sample.quote, selection: first.id)
                guard selection.status == .matched, selection.selected?.id == first.id else { throw CheckFailure.selectionMismatch }
                checks.append(Check(scenario: "selection", status: selection.status.rawValue, selected: selection.selected?.id, candidates: selection.candidateCount, originalTextKept: Array(selection.selected!.verses[0].text.unicodeScalars) == Array(first.verses[0].text.unicodeScalars)))
            }
        }
        let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(checks).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        print("Live Swift client contract checks passed:", checks.count)
    }
    enum CheckFailure: Error { case statusMismatch, originalTextChanged, selectionMismatch }
}
