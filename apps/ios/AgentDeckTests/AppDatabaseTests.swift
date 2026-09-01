import GRDB
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
        let capabilities = makeTestIdentity(peer: "capabilities").capabilities
        let source = RemoteConversationSource(
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
        )
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
                defaultModelID: nil,
                capabilities: capabilities
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
                source: source,
                kind: .agentEntrypoint,
                capabilities: capabilities
            )]
        )

        try AppDatabase(databaseURL: databaseURL).upsertSessions([section])

        // Released v3 databases predate GRDB's migration ledger. Removing the
        // ledger recreates that upgrade state while retaining the real schema/data.
        try DatabaseQueue(path: databaseURL.path).write { db in
            try db.drop(table: "grdb_migrations")
        }

        let relaunched = AppDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try relaunched.sessionSections().first?.sessions.first?.id, sessionID)
        let persistedSession = try relaunched.session(sessionID: sessionID)
        XCTAssertEqual(persistedSession?.previewText, "persist me")
        XCTAssertEqual(persistedSession?.kind, .agentEntrypoint)
        XCTAssertEqual(persistedSession?.source?.participantDisplay, "Alice")
        XCTAssertEqual(persistedSession?.capabilities?.attachments?.supported, true)
        XCTAssertEqual(try relaunched.sessionSections().first?.gateway.capabilities?.approvals?.exec, true)

        let appliedMigrations = try DatabaseQueue(path: databaseURL.path).read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        XCTAssertEqual(appliedMigrations, ["v3-baseline", "v3-session-capabilities"])
    }
}
