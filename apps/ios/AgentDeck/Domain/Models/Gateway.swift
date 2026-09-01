import Foundation

struct GatewayID: Hashable, Codable, Equatable, Sendable {
    let rawValue: String
}

struct ModelDescriptor: Equatable, Codable, Identifiable, Sendable {
    var id: String
    var label: String?
    var provider: String?
}

struct Gateway: Equatable, Identifiable, Sendable {
    let id: GatewayID
    var displayName: String
    var softwareID: String
    var softwareName: String?
    var softwareVersion: String?
    var protocolVersion: Int?
    var lastSeenAt: Date?
    var availableModels: [ModelDescriptor]
    var defaultModelID: String?
    var capabilities: RemoteRelayCapabilities? = nil
}
