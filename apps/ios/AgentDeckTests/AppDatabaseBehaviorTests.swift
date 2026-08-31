import Foundation
import XCTest
@testable import AgentDeck

final class AppDatabaseBehaviorTests: XCTestCase {
    func testOutgoingMessageAttachmentFailureAndRetryLifecycle() throws {
        try withSeededDatabase { database, sessionID in
            let draft = DraftAttachment(
                id: "draft-1",
                fileName: "photo.png",
                mimeType: "image/png",
                sizeBytes: 42,
                kind: .image,
                localURL: "/tmp/photo.png"
            )
            let messageID = try XCTUnwrap(database.insertLocalOutgoingMessage(
                text: "hello",
                sessionID: sessionID,
                deviceID: "ios",
                attachments: [draft]
            ))
            XCTAssertEqual(try database.draftAttachmentsForMessage(messageID: messageID), [draft])

            try database.markMessageFailed(messageID: messageID, error: "offline")
            var message = try XCTUnwrap(database.transcript(sessionID: sessionID, limit: 10).messages.first)
            XCTAssertEqual(message.deliveryState, .failed("offline"))
            XCTAssertEqual(message.attachments.first?.transferState, .failed)

            try database.prepareMessageForRetry(messageID: messageID)
            message = try XCTUnwrap(database.transcript(sessionID: sessionID, limit: 10).messages.first)
            XCTAssertEqual(message.deliveryState, .sending)
            XCTAssertEqual(message.attachments.first?.transferState, .pending)

            let uploaded = RelayAttachment(
                id: "draft-1",
                key: "att/server/photo.png",
                fileName: "photo.png",
                contentType: "image/png",
                size: 42,
                sha256: "hash",
                kind: .image,
                width: 10,
                height: 20,
                durationMS: nil,
                previewImageKey: nil,
                previewImageType: nil,
                previewSize: nil
            )
            try database.updateUploadedAttachments(messageID: messageID, attachments: [uploaded])
            try database.markMessageSent(messageID: messageID)
            message = try XCTUnwrap(database.transcript(sessionID: sessionID, limit: 10).messages.first)
            XCTAssertEqual(message.deliveryState, .sentToRelay)
            XCTAssertEqual(message.attachments.first?.objectKey, uploaded.key)
            XCTAssertEqual(message.attachments.first?.localCacheURL, draft.localURL)
        }
    }

    func testInboxIngestionHandlesStreamingAttachmentAndDeliveryReaction() throws {
        try withSeededDatabase { database, sessionID in
            let localID = try XCTUnwrap(database.insertLocalOutgoingMessage(
                text: "outgoing",
                sessionID: sessionID,
                deviceID: "ios"
            ))
            let reaction = makeRelayMessage(
                id: "reaction-1",
                from: "server",
                to: "ios",
                timestamp: 1_000,
                content: .reaction(RelayReactionContent(
                    type: "reaction",
                    targetMsgID: localID.rawValue,
                    emoji: "✅",
                    remove: false
                ))
            )
            _ = try database.ingestInboxEntries(
                [RelayInboxEntry(key: "msg/ios/reaction.json", message: reaction)],
                clientID: "ios"
            )

            let attachment = RelayAttachment(
                id: "file-1",
                key: "att/ios/file-1",
                fileName: "answer.txt",
                contentType: "text/plain",
                size: 6,
                sha256: nil,
                kind: .file,
                width: nil,
                height: nil,
                durationMS: nil,
                previewImageKey: nil,
                previewImageType: nil,
                previewSize: nil
            )
            let reply = makeRelayMessage(
                id: "reply-1",
                from: "server",
                to: "ios",
                timestamp: 2_000,
                content: .text(RelayTextContent(type: "text", text: "answer", attachments: [attachment])),
                delivery: RelayDelivery(stream: RelayDeliveryStream(streamID: "stream-1", seq: 2, state: "final"))
            )
            _ = try database.ingestInboxEntries(
                [RelayInboxEntry(key: "msg/ios/reply.json", message: reply)],
                clientID: "ios"
            )

            let messages = try database.transcript(sessionID: sessionID, limit: 10).messages
            XCTAssertEqual(messages.first(where: { $0.id == localID })?.deliveryState, .confirmed)
            let storedReply = try XCTUnwrap(messages.first(where: { $0.id.rawValue == "reply-1" }))
            XCTAssertEqual(storedReply.streamState, .complete)
            XCTAssertEqual(storedReply.attachments.first?.objectKey, attachment.key)
            XCTAssertEqual(storedReply.attachments.first?.transferState, .available)
        }
    }

    func testApprovalRequestAndResponsePersistResolution() throws {
        try withSeededDatabase { database, sessionID in
            let request = makeRelayMessage(
                id: "approval-message",
                from: "server",
                to: "ios",
                timestamp: 1_000,
                content: .approvalRequest(RelayApprovalRequestContent(
                    type: "approval_request",
                    approvalID: "approval-1",
                    approvalKind: "exec",
                    title: "Run command",
                    body: "git status",
                    allowedDecisions: ["allow", "deny"],
                    metadata: nil
                ))
            )
            _ = try database.ingestInboxEntries(
                [RelayInboxEntry(key: "msg/ios/request.json", message: request)],
                clientID: "ios"
            )
            var approval = try XCTUnwrap(database.transcript(sessionID: sessionID, limit: 10).messages.first)
            XCTAssertEqual(approval.execApproval?.approvalID, "approval-1")
            XCTAssertNil(approval.execApprovalResolution)

            let response = makeRelayMessage(
                id: "approval-response",
                from: "ios",
                to: "server",
                timestamp: 2_000,
                content: .approvalResponse(RelayApprovalResponseContent(
                    type: "approval_response",
                    approvalID: "approval-1",
                    decision: "allow",
                    metadata: nil
                ))
            )
            _ = try database.ingestInboxEntries(
                [RelayInboxEntry(key: "msg/server/response.json", message: response)],
                clientID: "ios"
            )
            approval = try XCTUnwrap(database.transcript(sessionID: sessionID, limit: 10).messages.first)
            XCTAssertEqual(approval.execApprovalResolution, ExecApprovalResolution(decision: "allow"))
        }
    }

    func testInboxHeadSurvivesNilSaveAndDatabaseReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("agentdeck.sqlite")
        let head = RelayHeadDoc(headKey: "msg/ios/head.json", headMsgID: "m1", headTS: 1_000)

        let first = AppDatabase(databaseURL: url)
        try first.saveInboxHead(clientID: "ios", head: head)
        try first.saveInboxHead(clientID: "ios", head: nil)

        XCTAssertEqual(try AppDatabase(databaseURL: url).loadLastSeenInboxKey(clientID: "ios"), head.headKey)
    }

    private func withSeededDatabase(_ body: (AppDatabase, SessionID) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = AppDatabase(databaseURL: directory.appendingPathComponent("agentdeck.sqlite"))
        let gatewayID = GatewayID(rawValue: "server")
        let sessionID = SessionID(rawValue: "server::main::agent:main:main")
        let route = RelayRoute(agentID: "main", conversationID: "agent:main:main", instanceID: nil)
        _ = try database.upsertSessions([GatewaySection(
            id: gatewayID,
            gateway: Gateway(
                id: gatewayID,
                displayName: "Server",
                softwareID: "openclaw",
                softwareName: "OpenClaw",
                softwareVersion: "test",
                protocolVersion: 3,
                lastSeenAt: Date(),
                availableModels: [],
                defaultModelID: nil
            ),
            sessions: [ChatSession(
                id: sessionID,
                gatewayID: gatewayID,
                agentID: "main",
                route: route,
                title: "Main",
                localTitle: nil,
                previewText: "",
                updatedAt: nil,
                unreadCount: 0,
                source: nil
            )]
        )])
        try body(database, sessionID)
    }
}
