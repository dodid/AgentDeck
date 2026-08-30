import Foundation

enum LocalDataAgeOption: String, CaseIterable, Identifiable, Sendable {
    case sevenDays

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .sevenDays:
            return String(localized: "7 days")
        }
    }

    func cutoffDate(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        }
    }
}

struct AttachmentCleanupPlan: Sendable {
    let localFilePaths: [String]
}