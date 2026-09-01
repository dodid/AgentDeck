import Foundation

struct SessionID: Hashable, Codable, Equatable, Identifiable, Sendable {
    let rawValue: String
    var id: String { rawValue }
}

struct SessionDisplayLabel: Equatable, Sendable {
    let primary: String
    let secondary: String?

    nonisolated var plainText: String {
        guard let secondary, !secondary.isEmpty else { return primary }
        return primary + " " + secondary
    }
}

enum ChatSessionKind: String, Codable, Equatable, Sendable {
    case conversation
    case agentEntrypoint
}

struct ChatSession: Equatable, Identifiable, Sendable {
    let id: SessionID
    let gatewayID: GatewayID
    let agentID: String
    let route: RelayRoute
    var title: String
    var localTitle: String?
    var previewText: String
    var updatedAt: Date?
    var unreadCount: Int
    var source: RemoteConversationSource?
    var kind: ChatSessionKind = .conversation
    var capabilities: RemoteRelayCapabilities? = nil
}

extension ChatSession {
    nonisolated func displayLabelParts(gatewayDisplayName _: String?) -> SessionDisplayLabel {
        let trimmedLocalTitle = localTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let title = trimmedLocalTitle, !title.isEmpty {
            return SessionDisplayLabel(primary: title, secondary: nil)
        }

        let remoteTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remoteTitle.isEmpty {
            return SessionDisplayLabel(primary: remoteTitle, secondary: sourceContextLabel)
        }

        let agentName = agentID.isEmpty ? "Main" : agentID
        let conversationID = route.conversationID ?? agentID
        return SessionDisplayLabel(
            primary: agentName,
            secondary: conversationID == agentID ? nil : conversationID
        )
    }

    nonisolated func displayLabel(gatewayDisplayName _: String?) -> String {
        displayLabelParts(gatewayDisplayName: nil).plainText
    }

    private nonisolated var sourceContextLabel: String? {
        guard let source else { return nil }
        let candidates = [source.threadDisplay, source.chatDisplay, source.participantDisplay, source.channel]
        return candidates.first { value in
            guard let value else { return false }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.caseInsensitiveCompare(title) != .orderedSame
        } ?? nil
    }
}

struct GatewaySection: Equatable, Identifiable, Sendable {
    let id: GatewayID
    let gateway: Gateway
    let sessions: [ChatSession]
}
