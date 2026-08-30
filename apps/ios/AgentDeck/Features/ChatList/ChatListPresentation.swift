import Foundation

struct ChatListRowViewData: Identifiable, Equatable {
    let id: SessionID
    let title: SessionDisplayLabel
    let previewText: String
    let timestampText: String
    let unreadCount: Int
    let requiresSubscription: Bool
}

struct ChatListSectionViewData: Identifiable, Equatable {
    let id: GatewayID
    let title: String
    let subtitle: String
    let rows: [ChatListRowViewData]
}
