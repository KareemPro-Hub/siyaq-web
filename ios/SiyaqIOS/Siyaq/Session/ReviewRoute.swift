import Foundation

/// مسارات شاشات المراجعة (بلا SwiftUI حتى تُختبر).
enum ReviewRoute: Hashable {
    /// نتيجة الاقتباس (مطابقة، أو اختيار موضع، أو عدم العثور).
    case review
    /// نتيجة موضع اختاره المستخدم.
    case selection(String)

    var isSelection: Bool {
        if case .selection = self { return true }
        return false
    }

    /// يضيف شاشة الموضع مرة واحدة فقط؛ نقرة مكررة لا تدفع شاشة ثانية فوقها.
    static func pushingSelection(_ id: String, onto path: [ReviewRoute]) -> [ReviewRoute] {
        guard !path.contains(where: { $0.isSelection }) else { return path }
        return path + [.selection(id)]
    }
}
