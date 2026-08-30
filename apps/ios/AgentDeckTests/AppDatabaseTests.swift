import XCTest
@testable import AgentDeck

final class AppDatabaseTests: XCTestCase {
    func testFreshV3DatabasePersistsAcrossLaunches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("agentdeck.sqlite")

        let gatewayID = GatewayID(rawValue: "openclaw-primary")
        let sessionID = SessionID(rawValue: "openclaw-primary::main::agent:main:main")
        let section = GatewaySection(
            id: gatewayID,
            gateway: Gateway(
                id: gatewayID,
                displayName: "OpenClaw",
                softwareID: "openclaw",
                softwareName: "OpenClaw",
                softwareVersion: "2026.7.1-2",
                protocolVersion: 3,
                lastSeenAt: Date(),
                availableModels: [],
                defaultModelID: nil
            ),
            sessions: [ChatSession(
                id: sessionID,
                gatewayID: gatewayID,
                agentID: "main",
                route: RelayRoute(agentID: "main", conversationID: "agent:main:main", instanceID: nil),
                title: "Main",
                localTitle: nil,
                previewText: "persist me",
                updatedAt: Date(),
                unreadCount: 0,
                source: nil
            )]
        )

        try AppDatabase(databaseURL: databaseURL).upsertSessions([section])

        let relaunched = AppDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try relaunched.sessionSections().first?.sessions.first?.id, sessionID)
        XCTAssertEqual(try relaunched.session(sessionID: sessionID)?.previewText, "persist me")
    }
}
