import Foundation
import Observation

@MainActor
@Observable
final class SessionInspectorViewModel {
    let environment: AppEnvironment
    let sessionID: SessionID
    var title: String = String(localized: "Session Info")
    var sessionTitle: String = String(localized: "Session")
    var gatewayID: String = ""
    var gatewayDisplayName: String = ""
    var agentID: String = ""
    var conversationID: String = ""
    var instanceID: String = ""
    var threadID: String = ""
    var localSessionTitle: String = ""
    var deviceName: String = ""
    var deviceID: String = ""
    var lastMessageFetchAt: Date?
    var isRefreshing = false

    init(environment: AppEnvironment, sessionID: SessionID) {
        self.environment = environment
        self.sessionID = sessionID
        Task {
            await load()
        }
    }

    func load() async {
        if let chatRepository = environment.chatRepository as? DefaultChatRepository,
           let session = try? await chatRepository.session(sessionID) {
            self.gatewayID = session.gatewayID.rawValue
            self.agentID = session.agentID
            self.conversationID = session.route.conversationID ?? ""
            self.instanceID = session.route.instanceID ?? ""
            self.threadID = session.id.rawValue
            self.localSessionTitle = session.localTitle ?? ""
            self.sessionTitle = session.displayLabel(gatewayDisplayName: nil)

            let sections = chatRepository.observeSessionSections()
            for await gatewaySections in sections {
                if let section = gatewaySections.first(where: { section in
                    section.sessions.contains(where: { $0.id == sessionID })
                }), let currentSession = section.sessions.first(where: { $0.id == sessionID }) {
                    self.gatewayDisplayName = section.gateway.displayName
                    self.localSessionTitle = currentSession.localTitle ?? ""
                    self.sessionTitle = currentSession.displayLabel(gatewayDisplayName: section.gateway.displayName)
                }
                break
            }
        }

        if let device = try? await environment.deviceRepository.loadDeviceProfile() {
            self.deviceName = device.displayName
            self.deviceID = device.clientID
        }

        self.lastMessageFetchAt = environment.syncActivityStore.lastFetchAt
    }

    func refreshSession() async {
        isRefreshing = true
        defer { isRefreshing = false }
        try? await environment.syncRepository.refreshNow()
        await load()
    }

    func renameSessionLocally(to title: String) async {
        guard let chatRepository = environment.chatRepository as? DefaultChatRepository else { return }
        try? await chatRepository.renameSessionLocally(sessionID, title: title)
        await load()
    }
}
