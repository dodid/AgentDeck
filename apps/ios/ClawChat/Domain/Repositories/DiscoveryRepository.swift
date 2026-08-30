import Foundation

protocol DiscoveryRepository: Sendable {
    func refreshGateways(force: Bool) async throws
    func observeGatewayList() -> AsyncStream<[GatewaySection]>
}
