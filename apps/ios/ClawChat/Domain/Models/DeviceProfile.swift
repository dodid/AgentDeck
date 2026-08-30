import Foundation

struct DeviceProfile: Equatable, Codable, Sendable {
    let clientID: String
    var displayName: String
    let createdAt: Date
}
