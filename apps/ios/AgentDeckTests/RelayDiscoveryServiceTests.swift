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
        XCTAssertEqual(sections.first?.sessions.first?.kind, .agentEntrypoint)
        XCTAssertEqual(sections.first?.sessions.first?.capabilities?.attachments?.supported, true)
    }

    func testDiscoveryRepresentsPublishedConversationAndPreservesSource() async throws {
        let store = TestObjectStore()
        let route = RelayRoute(agentID: "main", conversationID: "agent:main:telegram:direct:user-1", instanceID: "epoch-1")
        let conversation = RemoteConversationDescriptor(
            id: "agent:main:telegram:direct:user-1",
            displayTitle: "Alice",
            route: route,
            source: RemoteConversationSource(
                channel: "telegram",
                chatKind: "dm",
                accountID: nil,
                accountDisplay: nil,
                spaceID: nil,
                spaceDisplay: nil,
                chatID: nil,
                chatDisplay: nil,
                participantID: "user-1",
                participantDisplay: "Alice",
                threadID: nil,
                threadDisplay: nil,
                sharing: "private"
            ),
            updatedAt: Date().timeIntervalSince1970 * 1000
        )
        try await store.seedJSON(
            makeTestIdentity(peer: "server", conversations: [conversation]),
            key: "identity/server.json"
        )

        let sections = try await RelayDiscoveryService(store: store).discoverGateways()
        let session = try XCTUnwrap(sections.first?.sessions.first)
        XCTAssertEqual(session.kind, .conversation)
        XCTAssertEqual(session.source?.channel, "telegram")
        XCTAssertEqual(session.displayLabel(gatewayDisplayName: nil), "Alice telegram")
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
