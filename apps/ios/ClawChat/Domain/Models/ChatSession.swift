import Foundation

struct SessionID: Hashable, Codable, Equatable, Identifiable, Sendable {
    let rawValue: String
    var id: String { rawValue }
}

struct SessionDisplayLabel: Equatable, Sendable {
    let primary: String
    let secondary: String?

    var plainText: String {
        guard let secondary, !secondary.isEmpty else { return primary }
        return primary + " " + secondary
    }
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
}

extension ChatSession {
    var isFreeMainAgentSession: Bool {
        agentID == "main"
    }

    var requiresAgentSubscription: Bool {
        !isFreeMainAgentSession
    }

    func displayLabelParts(gatewayDisplayName _: String?) -> SessionDisplayLabel {
        let trimmedLocalTitle = localTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let title = trimmedLocalTitle, !title.isEmpty {
            return SessionDisplayLabel(primary: title, secondary: nil)
        }

        let agentName = agentID.isEmpty ? "Main" : agentID
        let conversationID = route.conversationID ?? agentID
        return SessionDisplayLabel(
            primary: agentName,
            secondary: conversationID == agentID ? nil : conversationID
        )
    }

    func displayLabel(gatewayDisplayName _: String?) -> String {
        displayLabelParts(gatewayDisplayName: nil).plainText
    }
}

struct GatewaySection: Equatable, Identifiable, Sendable {
    let id: GatewayID
    let gateway: Gateway
    let sessions: [ChatSession]
}
