import Foundation
import XCTest
@testable import ClawChat

final class RelayContractTests: XCTestCase {
    func testDecodesCanonicalV3Message() throws {
        let data = Data(#"{"msg_id":"m1","from":"ios","to":"server","ts_sent":1788000000000,"prev_key":null,"route":{"agent_id":"main","conversation_id":"agent:main:main"},"content":{"type":"text","text":"hello","attachments":null},"delivery":null,"status":null,"size":5}"#.utf8)
        let message = try JSONDecoder().decode(RelayMessage.self, from: data)
        XCTAssertEqual(message.route.agentID, "main")
        guard case .text(let content) = message.content else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(content.text, "hello")
    }

    func testRejectsLegacyFlatMessage() {
        let data = Data(#"{"msg_id":"m1","from":"ios","to":"server","ts_sent":1788000000000,"type":"text","body":"legacy"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(RelayMessage.self, from: data))
    }

    func testAcceptsOnlyV3Identity() throws {
        let json = #"{"peer":"server","display_name":"Server","role":"server","last_seen":1788000000000,"protocol":{"name":"r2-relay","version":3},"software":{"id":"openclaw","name":"OpenClaw","version":"2026.7.1-2"},"capabilities":{"messaging":{"text":true,"streaming":true,"reactions":true,"system_events":false},"conversations":{"list":true,"create":false,"reset":false,"archive":false,"threading":true},"agents":{"list":true,"multiple":true,"switch":true,"per_agent_models":true}},"agents":[],"conversations":[]}"#
        let identity = try JSONDecoder().decode(RemoteIdentityDoc.self, from: Data(json.utf8))
        XCTAssertTrue(RelayDiscoveryService.isSupportedIdentity(identity))

        let legacy = json.replacingOccurrences(of: #""version":3"#, with: #""version":2"#)
        let legacyIdentity = try JSONDecoder().decode(RemoteIdentityDoc.self, from: Data(legacy.utf8))
        XCTAssertFalse(RelayDiscoveryService.isSupportedIdentity(legacyIdentity))
    }

    func testLiveMinIORoundTripWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["CLAWCHAT_TEST_R2_ENDPOINT"],
              let bucket = environment["CLAWCHAT_TEST_R2_BUCKET"],
              let accessKeyID = environment["CLAWCHAT_TEST_R2_ACCESS_KEY_ID"],
              let secretAccessKey = environment["CLAWCHAT_TEST_R2_SECRET_ACCESS_KEY"] else {
            throw XCTSkip("Live object-store test is enabled only by the release-candidate workflow.")
        }

        let recipient = "ios-smoke-\(UUID().uuidString.lowercased())"
        let messageID = "message-\(UUID().uuidString.lowercased())"
        let service = RelayMessagingService(config: ConnectionConfig(
            endpoint: endpoint,
            bucket: bucket,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            region: "us-east-1",
            forcePathStyle: true
        ))

        _ = try await service.sendMessage(
            from: "clawchat-ci",
            target: RelaySendTarget(
                gatewayPeer: recipient,
                route: RelayRoute(agentID: "main", conversationID: "ci:main", instanceID: nil)
            ),
            text: "release candidate smoke",
            messageID: messageID
        )

        let result = try await service.collectInboxMessages(clientID: recipient, lastSeenKey: nil)
        XCTAssertEqual(result.messages.map(\.message.msgID), [messageID])
    }
}
