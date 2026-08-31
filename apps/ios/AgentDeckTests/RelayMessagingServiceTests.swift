import XCTest
@testable import AgentDeck

final class RelayMessagingServiceTests: XCTestCase {
    func testSendAndCollectPreservesOrderAttachmentsAndRoute() async throws {
        let store = TestObjectStore()
        let service = RelayMessagingService(store: store)
        let target = RelaySendTarget(
            gatewayPeer: "server",
            route: RelayRoute(agentID: "main", conversationID: "conversation-1", instanceID: "instance-1")
        )
        let attachment = RelayAttachment(
            id: "a1",
            key: "att/server/a1",
            fileName: "report.txt",
            contentType: "text/plain",
            size: 12,
            sha256: "abc",
            kind: .file,
            width: nil,
            height: nil,
            durationMS: nil,
            previewImageKey: nil,
            previewImageType: nil,
            previewSize: nil
        )

        _ = try await service.sendMessage(from: "ios", target: target, text: "first", messageID: "m1")
        _ = try await service.sendMessage(from: "ios", target: target, text: "second", messageID: "m2", attachments: [attachment])

        let batch = try await service.collectInboxMessages(clientID: "server", lastSeenKey: nil)
        XCTAssertEqual(batch.messages.map(\.message.msgID), ["m1", "m2"])
        XCTAssertEqual(batch.messages.last?.message.route, target.route)
        guard case .text(let content) = batch.messages.last?.message.content else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(content.attachments, [attachment])

        let empty = try await service.collectInboxMessages(clientID: "server", lastSeenKey: batch.head?.headKey)
        XCTAssertTrue(empty.messages.isEmpty)
    }

    func testSendRetriesAfterConcurrentHeadFailure() async throws {
        let store = TestObjectStore()
        await store.failNextHeadWrites(2)
        let service = RelayMessagingService(store: store)
        let target = RelaySendTarget(
            gatewayPeer: "server",
            route: RelayRoute(agentID: "main", conversationID: "conversation-1", instanceID: nil)
        )

        _ = try await service.sendMessage(from: "ios", target: target, text: "retry", messageID: "retry-message")

        let batch = try await service.collectInboxMessages(clientID: "server", lastSeenKey: nil)
        XCTAssertEqual(batch.messages.map(\.message.msgID), ["retry-message"])
    }

    func testApprovalResponseUsesCanonicalContent() async throws {
        let store = TestObjectStore()
        let service = RelayMessagingService(store: store)
        let target = RelaySendTarget(
            gatewayPeer: "server",
            route: RelayRoute(agentID: "main", conversationID: "conversation-1", instanceID: nil)
        )

        _ = try await service.sendApprovalResponse(
            from: "ios",
            target: target,
            approvalID: "approval-1",
            decision: "allow",
            messageID: "response-1"
        )

        let batch = try await service.collectInboxMessages(clientID: "server", lastSeenKey: nil)
        guard case .approvalResponse(let content) = batch.messages.first?.message.content else {
            return XCTFail("Expected approval response")
        }
        XCTAssertEqual(content.approvalID, "approval-1")
        XCTAssertEqual(content.decision, "allow")
    }

    func testBackfillMergesBothDirectionsFiltersConversationAndDeduplicates() async throws {
        let store = TestObjectStore()
        let service = RelayMessagingService(store: store)
        let clientTarget = RelaySendTarget(
            gatewayPeer: "ios",
            route: RelayRoute(agentID: "main", conversationID: "wanted", instanceID: nil)
        )
        let serverTarget = RelaySendTarget(
            gatewayPeer: "server",
            route: RelayRoute(agentID: "main", conversationID: "wanted", instanceID: nil)
        )
        let ignoredTarget = RelaySendTarget(
            gatewayPeer: "ios",
            route: RelayRoute(agentID: "main", conversationID: "ignored", instanceID: nil)
        )

        _ = try await service.sendMessage(from: "ios", target: serverTarget, text: "out", messageID: "out")
        _ = try await service.sendMessage(from: "server", target: ignoredTarget, text: "ignore", messageID: "ignore")
        _ = try await service.sendMessage(from: "server", target: clientTarget, text: "in", messageID: "in")

        let entries = try await service.loadThreadBackfill(
            clientID: "ios",
            gatewayPeer: "server",
            conversationID: "wanted",
            limit: 10
        )
        XCTAssertEqual(Set(entries.map(\.message.msgID)), Set(["out", "in"]))
    }
}
