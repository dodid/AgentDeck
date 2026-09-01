import XCTest
@testable import AgentDeck

final class AppFeatureLogicTests: XCTestCase {
    func testConnectionConfigFileImportsAliasesAndPreservesUnspecifiedValues() throws {
        let original = ConnectionConfig(
            endpoint: "old-endpoint",
            bucket: "old-bucket",
            accessKeyID: "old-access",
            secretAccessKey: "old-secret",
            region: "us-east-1",
            forcePathStyle: false
        )
        let imported = try ConnectionConfigTextFile.applying(
            """
            # exported configuration
            endpoint = https://example.invalid
            accessKeyId = new-access
            secret-access-key = new-secret=value
            """,
            to: original
        )

        XCTAssertEqual(imported.endpoint, "https://example.invalid")
        XCTAssertEqual(imported.bucket, original.bucket)
        XCTAssertEqual(imported.accessKeyID, "new-access")
        XCTAssertEqual(imported.secretAccessKey, "new-secret=value")
        XCTAssertEqual(imported.region, "auto")
        XCTAssertTrue(imported.forcePathStyle)
    }

    func testConnectionConfigFileRejectsFilesWithoutSupportedAssignments() {
        XCTAssertThrowsError(try ConnectionConfigTextFile.applying("# comments only", to: .empty))
    }

    func testCommandSuggestionsArePlatformSpecificAndPrefixFiltered() {
        let engine = CommandSuggestionEngine()
        XCTAssertEqual(engine.commandSuggestions(for: "/sta", platform: "openclaw").map(\.title), ["/status"])
        XCTAssertEqual(engine.commandSuggestions(for: "/ret", platform: "hermes").map(\.title), ["/retry"])
        XCTAssertTrue(engine.commandSuggestions(for: "/status complete", platform: "openclaw").isEmpty)
    }

    func testModelSuggestionsFilterAndStopAtExactModel() {
        let engine = CommandSuggestionEngine()
        let models = [
            ModelDescriptor(id: "openrouter/fast", label: "Fast", provider: "openrouter"),
            ModelDescriptor(id: "openrouter/deep", label: "Deep", provider: "openrouter")
        ]
        XCTAssertEqual(engine.modelSuggestions(for: "/model dee", models: models).map(\.id), ["openrouter/deep"])
        XCTAssertTrue(engine.modelSuggestions(for: "/model openrouter/deep", models: models).isEmpty)
    }

    func testSessionDisplayRules() {
        let gatewayID = GatewayID(rawValue: "server")
        let main = ChatSession(
            id: SessionID(rawValue: "main"),
            gatewayID: gatewayID,
            agentID: "main",
            route: RelayRoute(agentID: "main", conversationID: "conversation", instanceID: nil),
            title: "Ignored",
            localTitle: "  Custom title  ",
            previewText: "",
            updatedAt: nil,
            unreadCount: 0,
            source: nil
        )
        XCTAssertEqual(main.displayLabel(gatewayDisplayName: nil), "Custom title")

        let secondary = ChatSession(
            id: SessionID(rawValue: "secondary"),
            gatewayID: gatewayID,
            agentID: "research",
            route: RelayRoute(agentID: "research", conversationID: "thread-42", instanceID: nil),
            title: "Research",
            localTitle: nil,
            previewText: "",
            updatedAt: nil,
            unreadCount: 0,
            source: nil
        )
        XCTAssertEqual(secondary.displayLabel(gatewayDisplayName: nil), "Research")
    }
}
