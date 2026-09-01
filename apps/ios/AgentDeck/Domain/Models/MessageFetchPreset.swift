import Foundation

enum MessageFetchPreset: String, Codable, CaseIterable, Sendable {
    case responsive
    case balanced
    case efficient

    var intervalSeconds: Int {
        switch self {
        case .responsive: return 5
        case .balanced: return 15
        case .efficient: return 60
        }
    }

    var approximateFetchesPerHour: Int {
        3_600 / intervalSeconds
    }

    var localizedLabel: String {
        switch self {
        case .responsive: return String(localized: "Responsive · every 5 sec")
        case .balanced: return String(localized: "Balanced · every 15 sec")
        case .efficient: return String(localized: "Efficient · every 60 sec")
        }
    }
}
