import Foundation
import Observation

@MainActor
@Observable
final class ChatListViewModel {
    let environment: AppEnvironment
    var sections: [ChatListSectionViewData] = []
    var isRefreshing = false
    var errorMessage: String?

    init(environment: AppEnvironment) {
        self.environment = environment

        Task {
            if let chatRepository = environment.chatRepository as? DefaultChatRepository {
                let stream = chatRepository.observeSessionSections()
                for await gatewaySections in stream {
                    self.sections = gatewaySections.map(Self.present)
                }
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await environment.discoveryRepository.refreshGateways(force: true)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func present(_ section: GatewaySection) -> ChatListSectionViewData {
        let subtitle = section.gateway.availableModels.isEmpty
            ? section.rowsCountText
            : section.rowsCountText + " · " + modelsCountText(for: section.gateway.availableModels.count)

        return ChatListSectionViewData(
            id: section.id,
            title: section.gateway.displayName,
            subtitle: subtitle,
            rows: section.sessions.map { session in
                ChatListRowViewData(
                    id: session.id,
                    title: session.displayLabelParts(gatewayDisplayName: section.gateway.displayName),
                    previewText: session.previewText.isEmpty ? String(localized: "No recent message") : session.previewText,
                    timestampText: timestampText(for: session.updatedAt),
                    unreadCount: session.unreadCount,
                    requiresSubscription: session.requiresAgentSubscription
                )
            }
        )
    }

    private static func timestampText(for date: Date?) -> String {
        guard let date else { return "" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func modelsCountText(for count: Int) -> String {
        if count == 1 {
            return String(localized: "1 model")
        }
        return String.localizedStringWithFormat(String(localized: "%lld models"), count)
    }
}

private extension GatewaySection {
    var rowsCountText: String {
        let count = sessions.count
        if count == 1 {
            return String(localized: "1 chat")
        }
        return String.localizedStringWithFormat(String(localized: "%lld chats"), count)
    }
}
