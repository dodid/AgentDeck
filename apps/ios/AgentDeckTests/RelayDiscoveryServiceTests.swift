import XCTest
@testable import AgentDeck

final class RelayDiscoveryServiceTests: XCTestCase {
    func testDiscoveryFiltersUnsupportedStaleAndClientIdentities() async throws {
        let store = TestObjectStore()
        let route = RelayRoute(agentID: "main", conversationID: "agent:main:main", instanceID: nil)
        let agent = RemoteAgentDescriptor(
            id: "main",
            displayName: "Main Agent",
            description: nil,
            isDefault: true,
            models: RemoteIdentityModelCapabilities(
                available: [RemoteIdentityModelInfo(id: "provider/model", label: "Model", provider: "provider")],
                default: "provider/model"
            ),
            defaultRoute: route,
            capabilities: nil
        )
        try await store.seedJSON(makeTestIdentity(peer: "fresh-server", agents: [agent]), key: "identity/fresh-server.json")
        try await store.seedJSON(makeTestIdentity(peer: "client", role: "client"), key: "identity/client.json")
        try await store.seedJSON(makeTestIdentity(peer: "legacy", protocolVersion: 2), key: "identity/legacy.json")
        try await store.seedJSON(
            makeTestIdentity(peer: "stale", lastSeenMS: Date().addingTimeInterval(-13 * 60 * 60).timeIntervalSince1970 * 1000),
            key: "identity/stale.json"
        )

        let sections = try await RelayDiscoveryService(store: store).discoverGateways()

        XCTAssertEqual(sections.map(\.gateway.id.rawValue), ["fresh-server"])
        XCTAssertEqual(sections.first?.gateway.defaultModelID, "provider/model")
        XCTAssertEqual(sections.first?.sessions.map(\.id.rawValue), ["fresh-server::main::agent:main:main"])
    }

    func testDiscoveryRejectsOnlyUnsupportedIdentities() async throws {
        let store = TestObjectStore()
        try await store.seedJSON(makeTestIdentity(peer: "legacy", protocolVersion: 2), key: "identity/legacy.json")

        do {
            _ = try await RelayDiscoveryService(store: store).discoverGateways()
            XCTFail("Expected unsupported protocol error")
        } catch RelayDiscoveryError.unsupportedProtocol {
            // Expected.
        }
    }

    func testDiscoveryReportsNoGatewayForEmptyRelay() async throws {
        do {
            _ = try await RelayDiscoveryService(store: TestObjectStore()).discoverGateways()
            XCTFail("Expected no gateways error")
        } catch RelayDiscoveryError.noGatewaysFound {
            // Expected.
        }
    }
}
