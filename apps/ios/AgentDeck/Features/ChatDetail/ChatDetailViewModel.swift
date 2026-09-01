import Foundation
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class ChatDetailViewModel {
    let environment: AppEnvironment
    let sessionID: SessionID
    let scrollCoordinator = ChatScrollCoordinator()

    var title = SessionDisplayLabel(primary: String(localized: "Session"), secondary: nil)
    var items: [TranscriptDisplayItem] = []
    var draftText: String = ""
    var draftAttachments: [DraftAttachment] = []
    var pendingPhotosPickerItems: [PhotosPickerItem] = []
    var isSending = false
    var isDictating = false
    var isLoadingOlder = false
    var canLoadOlder = false
    var errorMessage: String?
    var scrollToBottomRequestToken: Int = 0
    var commandSuggestions: [CommandSuggestionViewData] = []
    var modelSuggestions: [ModelSuggestionViewData] = []
    var selectedSuggestionIndex: Int = 0
    var availableModels: [ModelDescriptor] = []
    var isFetchingMessages = false
    var hasFetchError = false
    var didRecentlyFetchMessages = false
    var appearanceRenderToken: Int = 0
    var approvalStates: [String: ApprovalCardState] = [:]

    var hasSuggestions: Bool {
        !commandSuggestions.isEmpty || !modelSuggestions.isEmpty
    }

    var hasContent: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftAttachments.isEmpty
    }

    var composerPlaceholder: String {
        return hasSuggestions ? String(localized: "Type a command…") : String(localized: "Message…")
    }

    private var transcriptLimit: Int = 50
    private let presenter = TranscriptPresenter()
    private let suggestionEngine = CommandSuggestionEngine()
    private let speechTranscriber = SpeechTranscriber()
    private var speechDraftPrefix = ""
    private var platform = "openclaw"

    init(environment: AppEnvironment, sessionID: SessionID) {
        self.environment = environment
        self.sessionID = sessionID
        environment.syncActivityStore.hasVisibleChat = true

        Task {
            if let chatRepository = environment.chatRepository as? DefaultChatRepository {
                if let session = try? await chatRepository.session(sessionID) {
                    self.title = session.displayLabelParts(gatewayDisplayName: nil)
                }

                let sections = chatRepository.observeSessionSections()
                for await gatewaySections in sections {
                    if let section = gatewaySections.first(where: { section in
                        section.sessions.contains(where: { $0.id == sessionID })
                    }), let session = section.sessions.first(where: { $0.id == sessionID }) {
                        self.title = session.displayLabelParts(gatewayDisplayName: section.gateway.displayName)
                        self.platform = section.gateway.softwareID
                        self.availableModels = section.gateway.availableModels
                        self.updateSuggestions()
                    } else if let session = try? await chatRepository.session(sessionID) {
                        self.title = session.displayLabelParts(gatewayDisplayName: nil)
                        if self.availableModels.isEmpty {
                            self.updateSuggestions()
                        }
                    }
                }
            }
        }

        Task {
            let stream = environment.chatRepository.observeTranscript(sessionID: sessionID, limit: transcriptLimit)
            for await page in stream {
                self.canLoadOlder = page.canLoadMore
                self.items = self.presenter.present(page.messages)
                self.restoreApprovalStates(from: self.items)
                self.environment.syncActivityStore.hasActiveStreaming = self.items.contains { item in
                    if case .streaming = item { return true }
                    return false
                }
                // Seed download manager from local files so existing images render instantly
                self.seedAttachmentCacheFromTranscript(page.messages)
                if self.scrollCoordinator.shouldAutoScrollAfterTranscriptUpdate() {
                    self.scrollToBottomRequestToken += 1
                }
            }
        }

        Task {
            while !Task.isCancelled {
                self.isFetchingMessages = environment.syncActivityStore.isFetchingMessages
                self.hasFetchError = environment.syncActivityStore.lastFetchErrorMessage != nil
                self.didRecentlyFetchMessages = environment.syncActivityStore.didRecentlyFetchMessages
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

    }

    deinit {
        MainActor.assumeIsolated {
            speechTranscriber.stop(notify: false)
            environment.syncActivityStore.hasVisibleChat = false
            environment.syncActivityStore.hasActiveStreaming = false
        }
    }

    func applyAppearanceChange() {
        appearanceRenderToken += 1
    }

    func setDraftText(_ value: String) {
        if isDictating {
            stopDictation()
        }
        draftText = value
        updateSuggestions(resetSelection: false)
    }

    func send() async {
        if isDictating {
            stopDictation()
        }
        guard !isSending else { return }
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draftAttachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        isSending = true

        if let chatRepository = environment.chatRepository as? DefaultChatRepository,
           let syncRepository = environment.syncRepository as? DefaultSyncRepository {
            do {
                let messageID = try await chatRepository.sendMessageLocally(trimmed, attachments: attachments, to: sessionID)
                draftText = ""
                draftAttachments = []
                pendingPhotosPickerItems = []
                dismissSuggestions()
                errorMessage = nil
                scrollCoordinator.requestJumpToBottom()
                scrollToBottomRequestToken += 1

                if let messageID {
                    Task {
                        defer { self.isSending = false }
                        do {
                            try await syncRepository.sendExistingLocalMessage(trimmed, messageID: messageID, to: self.sessionID)
                        } catch {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                } else {
                    isSending = false
                }
                return
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
                return
            }
        }

        defer { isSending = false }
        do {
            try await environment.syncRepository.sendMessage(trimmed, attachments: attachments, to: sessionID)
            draftText = ""
            draftAttachments = []
            pendingPhotosPickerItems = []
            dismissSuggestions()
            errorMessage = nil
            scrollCoordinator.requestJumpToBottom()
            scrollToBottomRequestToken += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadOlder(topVisibleID: String?) async {
        guard !isLoadingOlder, canLoadOlder else { return }
        scrollCoordinator.willLoadOlder(topVisibleID: topVisibleID)
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        transcriptLimit = min(transcriptLimit + 50, 500)

        do {
            try await environment.syncRepository.backfill(sessionID: sessionID, limit: transcriptLimit)
            if let chatRepository = environment.chatRepository as? DefaultChatRepository {
                try await chatRepository.refreshSession(sessionID)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectCommandSuggestion(_ suggestion: CommandSuggestionViewData) {
        draftText = suggestion.title + " "
        updateSuggestions()
    }

    func selectModelSuggestion(_ suggestion: ModelSuggestionViewData) {
        draftText = "/model " + suggestion.id
        updateSuggestions()
    }

    func moveSuggestionSelection(delta: Int) {
        let count = modelSuggestions.isEmpty ? commandSuggestions.count : modelSuggestions.count
        guard count > 0 else { return }
        selectedSuggestionIndex = min(max(selectedSuggestionIndex + delta, 0), count - 1)
    }

    func dismissSuggestions() {
        commandSuggestions = []
        modelSuggestions = []
        selectedSuggestionIndex = 0
    }

    func submitComposer() async {
        guard !isSending else { return }
        if hasSuggestions {
            applySelectedSuggestionIfNeeded()
        } else {
            await send()
        }
    }

    func applySelectedSuggestionIfNeeded() {
        if !modelSuggestions.isEmpty, modelSuggestions.indices.contains(selectedSuggestionIndex) {
            selectModelSuggestion(modelSuggestions[selectedSuggestionIndex])
        } else if commandSuggestions.indices.contains(selectedSuggestionIndex) {
            selectCommandSuggestion(commandSuggestions[selectedSuggestionIndex])
        }
    }

    func didRestoreOlderScrollPosition() {
        scrollCoordinator.didFinishLoadingOlder()
    }

    func updateNearBottom(_ value: Bool) {
        scrollCoordinator.updateNearBottom(value)
    }

    func jumpToBottom() {
        scrollCoordinator.requestJumpToBottom()
        scrollToBottomRequestToken += 1
    }

    func addAttachment(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let contentType = item.supportedContentTypes.first
            let mimeType = contentType?.preferredMIMEType
            let kind: AttachmentKind = {
                guard let ct = contentType else { return .file }
                if ct.conforms(to: .image) { return .image }
                if ct.conforms(to: .movie) || ct.conforms(to: .video) { return .video }
                if ct.conforms(to: .audio) { return .audio }
                return .file
            }()
            let ext = contentType?.preferredFilenameExtension ?? "dat"
            let fileName = "attachment-\(UUID().uuidString.prefix(8).lowercased()).\(ext)"

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("agentdeck-drafts", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let localURL = tempDir.appendingPathComponent(fileName)
            try? data.write(to: localURL)

            let draft = DraftAttachment(
                id: UUID().uuidString.lowercased(),
                fileName: fileName,
                mimeType: mimeType,
                sizeBytes: data.count,
                kind: kind,
                localURL: localURL.path
            )
            draftAttachments.append(draft)
        }
    }

    func removeAttachment(_ attachment: DraftAttachment) {
        draftAttachments.removeAll(where: { $0.id == attachment.id })
        if let localURL = attachment.localURL {
            try? FileManager.default.removeItem(atPath: localURL)
        }
    }

    func handlePhotosPickerChange() {
        let selectedItems = pendingPhotosPickerItems
        pendingPhotosPickerItems = []

        let existingIDs = Set(draftAttachments.map(\.id))
        for item in selectedItems {
            let itemID = item.itemIdentifier ?? UUID().uuidString
            if !existingIDs.contains(itemID) {
                addAttachment(item)
            }
        }
    }

    func toggleDictation() {
        if isDictating {
            stopDictation()
        } else {
            Task {
                await startDictation()
            }
        }
    }

    func retryMessage(_ rawMessageID: String) async {
        guard let chatRepository = environment.chatRepository as? DefaultChatRepository,
              let syncRepository = environment.syncRepository as? DefaultSyncRepository else {
            return
        }

        let messageID = MessageID(rawValue: rawMessageID)

        do {
            try chatRepository.database.prepareMessageForRetry(messageID: messageID)
            await chatRepository.publishTranscript(for: sessionID, limit: transcriptLimit)
            errorMessage = nil
            try await syncRepository.sendExistingLocalMessage(messageID: messageID, to: sessionID)
        } catch {
            errorMessage = error.localizedDescription
            await chatRepository.publishTranscript(for: sessionID, limit: transcriptLimit)
        }
    }

    func approvalState(for approval: ExecApprovalMetadata) -> ApprovalCardState {
        approvalStates[approval.approvalID] ?? .pending
    }

    func sendApproval(_ decision: ApprovalDecision, for item: TranscriptItemViewData) async {
        guard let approval = item.execApproval else { return }
        let id = approval.approvalID
        let currentState = approvalStates[id] ?? .pending
        switch currentState {
        case .sending, .resolved:
            return
        case .pending, .failed:
            break
        }

        approvalStates[id] = .sending(decision)
        do {
            try await environment.syncRepository.sendApprovalResponse(
                approvalID: id,
                decision: decision.rawValue,
                to: sessionID
            )
            approvalStates[id] = .resolved(decision)
            errorMessage = nil
        } catch {
            approvalStates[id] = .failed(decision, error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func restoreApprovalStates(from items: [TranscriptDisplayItem]) {
        for item in items {
            guard case .message(let message) = item, let approval = message.execApproval else { continue }
            if let resolved = message.execApprovalResolution.flatMap({ ApprovalDecision(rawValue: $0.decision) }) {
                approvalStates[approval.approvalID] = .resolved(resolved)
            } else if approvalStates[approval.approvalID] == nil {
                approvalStates[approval.approvalID] = .pending
            }
        }
    }

    private func seedAttachmentCacheFromTranscript(_ messages: [ChatMessage]) {
        let downloadManager = AttachmentDownloadManager.shared

        for message in messages {
            for attachment in message.attachments {
                guard let localPath = attachment.localCacheURL, !localPath.isEmpty else { continue }
                let localURL = localPath.hasPrefix("file://")
                    ? URL(string: localPath)
                    : URL(fileURLWithPath: localPath)
                guard let localURL else { continue }
                let standardizedPath = localURL.standardizedFileURL.path
                guard FileManager.default.fileExists(atPath: standardizedPath) else { continue }

                downloadManager.seedFromLocalFile(objectKey: attachment.objectKey, localPath: standardizedPath)

                // For images, the local original can stand in for the preview key too.
                if attachment.kind == .image,
                   let previewObjectKey = attachment.previewObjectKey,
                   !previewObjectKey.isEmpty {
                    downloadManager.seedFromLocalFile(objectKey: previewObjectKey, localPath: standardizedPath)
                }
            }
        }
    }

    private func updateSuggestions(resetSelection: Bool = true) {
        let previous = selectedSuggestionIndex
        commandSuggestions = suggestionEngine.commandSuggestions(for: draftText, platform: platform)
        modelSuggestions = suggestionEngine.modelSuggestions(for: draftText, models: availableModels)
        let count = modelSuggestions.isEmpty ? commandSuggestions.count : modelSuggestions.count
        if count == 0 {
            selectedSuggestionIndex = 0
        } else if resetSelection {
            selectedSuggestionIndex = 0
        } else {
            selectedSuggestionIndex = min(previous, count - 1)
        }
    }

    private func startDictation() async {
        guard !isSending, !isDictating else { return }
        errorMessage = nil
        speechDraftPrefix = draftText

        do {
            try await speechTranscriber.start(
                onUpdate: { [weak self] transcription in
                    self?.applyDictation(transcription)
                },
                onCompletion: { [weak self] result in
                    self?.finishDictation(result)
                }
            )
            isDictating = true
        } catch {
            speechDraftPrefix = ""
            errorMessage = error.localizedDescription
        }
    }

    private func stopDictation() {
        speechTranscriber.stop()
        isDictating = false
        speechDraftPrefix = ""
    }

    private func applyDictation(_ transcription: String) {
        draftText = mergedSpeechDraft(prefix: speechDraftPrefix, transcription: transcription)
        updateSuggestions(resetSelection: false)
    }

    private func finishDictation(_ result: Result<Void, Error>) {
        isDictating = false
        speechDraftPrefix = ""
        if case .failure(let error) = result {
            errorMessage = error.localizedDescription
        }
    }

    private func mergedSpeechDraft(prefix: String, transcription: String) -> String {
        guard !transcription.isEmpty else { return prefix }
        guard !prefix.isEmpty else { return transcription }

        if prefix.last?.isWhitespace == true {
            return prefix + transcription
        }
        return prefix + " " + transcription
    }
}
