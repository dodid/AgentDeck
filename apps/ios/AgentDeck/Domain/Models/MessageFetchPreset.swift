import Foundation

enum MessageFetchPreset: String, Codable, CaseIterable, Sendable {
    case responsive
    case balanced
    case efficient

    var intervalSeconds: Int {
        switch self {
        case .responsive: return 2
        case .balanced: return 5
        case .efficient: return 10
        }
    }

    var localizedLabel: String {
        switch self {
        case .responsive: return String(localized: "Responsive · every 2 sec")
        case .balanced: return String(localized: "Balanced · every 5 sec")
        case .efficient: return String(localized: "Efficient · every 10 sec")
        }
    }
}
