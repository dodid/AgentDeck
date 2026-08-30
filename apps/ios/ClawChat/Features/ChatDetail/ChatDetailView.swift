import AVFoundation
import Combine
import Photos
import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import UIKit

struct ChatDetailView: View {
    @State var viewModel: ChatDetailViewModel
    @Namespace private var attachmentViewerTransition
    @State private var visibleTopMessageID: String?
    @State private var showingInfo = false
    @State private var didPerformInitialScroll = false
    @State private var presentedAttachment: PresentedAttachment?
    @State private var pendingAttachmentAction: PendingAttachmentAction?
    @State private var attachmentDownloadManager = AttachmentDownloadManager.shared
    @State private var saveConfirmationMessage: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        transcriptView
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    inputFocused = false
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if viewModel.hasSuggestions {
                        ComposerSuggestionsView(
                            commandSuggestions: viewModel.commandSuggestions,
                            modelSuggestions: viewModel.modelSuggestions,
                            selectedIndex: viewModel.selectedSuggestionIndex,
                            style: transcriptStyle,
                            onSelectCommand: { viewModel.selectCommandSuggestion($0) },
                            onSelectModel: { viewModel.selectModelSuggestion($0) }
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)
                        .padding(.top, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    ChatComposerView(viewModel: viewModel, style: transcriptStyle, inputFocused: $inputFocused) {
                        Task { await viewModel.submitComposer() }
                    }
                }
                .background(AppTheme.bg)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppTheme.bg.opacity(0.001))
                        .frame(height: 1)
                        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                        .allowsHitTesting(false)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(presentedAttachment == nil ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SessionTitleView(
                        label: viewModel.title,
                        isFetchingMessages: viewModel.isFetchingMessages
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showingInfo) {
                SessionInspectorView(viewModel: SessionInspectorViewModel(environment: viewModel.environment, sessionID: viewModel.sessionID))
                    .presentationDetents([.large])
            }
            .sheet(isPresented: Binding(
                get: { viewModel.showingPaywall },
                set: { viewModel.showingPaywall = $0 }
            )) {
                PaywallView(controller: viewModel.environment.subscriptionController)
                    .presentationDetents([.large])
            }
            .alert(
                String(localized: "Attachment Error"),
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                ),
                actions: {
                    Button(String(localized: "OK"), role: .cancel) {
                        viewModel.errorMessage = nil
                    }
                },
                message: {
                    Text(viewModel.errorMessage ?? String(localized: "This attachment could not be opened."))
                }
            )
            .onAppear {
                AttachmentDownloadBootstrap.configureIfNeeded(environment: viewModel.environment)
            }
            .onChange(of: pendingAttachmentActionStateToken) { _, token in
                guard token != "idle" else { return }
                resumePendingAttachmentActionIfPossible()
            }
            .overlay {
                if let attachment = presentedAttachment {
                    AttachmentViewerScreen(
                        attachment: attachment,
                        transitionNamespace: attachmentViewerTransition,
                        onShare: { sharedURL in
                            AttachmentSharePresenter.present(url: sharedURL)
                        },
                        onSave: { savedURL in
                            AttachmentSavePresenter.save(url: savedURL) { result in
                                switch result {
                                case .success:
                                    showSaveConfirmation()
                                case .failure(let error):
                                    viewModel.errorMessage = error.localizedDescription
                                }
                            }
                        },
                        onDismiss: dismissPresentedAttachment
                    )
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
            .overlay(alignment: .top) {
                if let saveConfirmationMessage {
                    AttachmentSaveConfirmationBanner(message: saveConfirmationMessage)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1100)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: presentedAttachment != nil)
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: saveConfirmationMessage != nil)
            .background(AppTheme.bg)
    }

    private var liveAppearance: AppearanceSettings {
        viewModel.environment.chatAppearanceController.appearance
    }

    private var transcriptStyle: ChatAppearanceStyle {
        ChatAppearanceStyle(liveAppearance)
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                if viewModel.items.isEmpty {
                    ContentUnavailableView("No Messages", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.bg)
                } else {
                    List {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            transcriptRow(item)
                                .id(item.id)
                                .onAppear {
                                    if index > 0, case .message(let message) = item {
                                        visibleTopMessageID = message.id
                                    }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(AppTheme.bg)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("transcript-bottom-anchor")
                            .listRowSeparator(.hidden)
                            .listRowBackground(AppTheme.bg)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.bg)
                    .id("\(transcriptStyle.renderKey)-\(viewModel.appearanceRenderToken)")
                    .onAppear {
                        guard !didPerformInitialScroll else { return }
                        didPerformInitialScroll = true
                        scrollToBottom(using: proxy, animated: false)
                    }
                    .onChange(of: transcriptStyle.renderKey) { _, _ in
                        viewModel.applyAppearanceChange()
                    }
                    .refreshable {
                        await viewModel.loadOlder(topVisibleID: visibleTopMessageID)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onScrollGeometryChange(for: Bool.self, of: { geometry in
                        let distanceFromBottom = max(geometry.contentSize.height - geometry.visibleRect.maxY, 0)
                        return distanceFromBottom <= 120
                    }, action: { _, isNearBottom in
                        viewModel.updateNearBottom(isNearBottom)
                    })
                    .onChange(of: viewModel.scrollToBottomRequestToken) { _, _ in
                        scrollToBottom(using: proxy, animated: true)
                    }
                    .onChange(of: viewModel.isLoadingOlder) { wasLoading, isLoading in
                        if wasLoading && !isLoading, let preserved = viewModel.scrollCoordinator.preservedTopMessageID {
                            proxy.scrollTo(preserved, anchor: .top)
                            viewModel.didRestoreOlderScrollPosition()
                        }
                    }
                    .onChange(of: inputFocused) { _, isFocused in
                        if isFocused {
                            scrollToBottom(using: proxy, animated: true)
                        }
                    }
                }

                if viewModel.scrollCoordinator.showJumpToBottom {
                    Button {
                        viewModel.jumpToBottom()
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(transcriptStyle.jumpToBottomIconFont)
                            .foregroundStyle(AppTheme.blue)
                            .padding(10)
                            .background(AppTheme.panel, in: Circle())
                    }
                    .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 2)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
            .background(AppTheme.bg)
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        Task { @MainActor in
            await Task.yield()
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("transcript-bottom-anchor", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("transcript-bottom-anchor", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func transcriptRow(_ item: TranscriptDisplayItem) -> some View {
        switch item {
        case .dateSeparator(let separator):
            TranscriptRows.dateSeparator(separator, style: transcriptStyle)
        case .message(let message):
            if transcriptStyle.isTerminal {
                TranscriptRows.terminalRow(
                    message,
                    style: transcriptStyle,
                    approvalState: message.execApproval.map { viewModel.approvalState(for: $0) } ?? .pending,
                    transitionNamespace: attachmentViewerTransition,
                    selectedAttachmentID: presentedAttachmentSourceID,
                    busyAttachmentID: busyAttachmentID,
                    onAttachmentTap: handleAttachmentTap,
                    onAttachmentShare: handleAttachmentShare,
                    onAttachmentRetry: handleAttachmentRetry
                ) { decision in
                    Task { await viewModel.sendApproval(decision, for: message) }
                }
            } else {
                TranscriptRows.bubbleRow(
                    message,
                    style: transcriptStyle,
                    approvalState: message.execApproval.map { viewModel.approvalState(for: $0) } ?? .pending,
                    transitionNamespace: attachmentViewerTransition,
                    selectedAttachmentID: presentedAttachmentSourceID,
                    busyAttachmentID: busyAttachmentID,
                    onAttachmentTap: handleAttachmentTap,
                    onAttachmentShare: handleAttachmentShare,
                    onAttachmentRetry: handleAttachmentRetry
                ) { decision in
                    Task { await viewModel.sendApproval(decision, for: message) }
                }
            }
        case .streaming(let streaming):
            TranscriptRows.streamingRow(streaming, style: transcriptStyle)
        }
    }

    private func handleAttachmentTap(_ attachment: TranscriptAttachmentViewData) {
        performAttachmentAction(.open, for: attachment)
    }

    private func handleAttachmentShare(_ attachment: TranscriptAttachmentViewData) {
        performAttachmentAction(.share, for: attachment)
    }

    private func handleAttachmentRetry(_ attachment: TranscriptAttachmentViewData) {
        Task {
            await viewModel.retryMessage(attachment.messageID)
        }
    }

    private func performAttachmentAction(_ action: AttachmentAction, for attachment: TranscriptAttachmentViewData) {
        if openAttachmentIfAvailable(attachment, action: action) {
            return
        }

        let objectKey = requiredDownloadObjectKey(for: attachment, action: action)
        pendingAttachmentAction = PendingAttachmentAction(
            attachment: attachment,
            action: action,
            objectKey: objectKey
        )

        if attachmentDownloadManager.state(for: objectKey) == nil {
            attachmentDownloadManager.download(objectKey: objectKey, environment: viewModel.environment)
            return
        }

        viewModel.errorMessage = attachmentFailureMessage(for: attachment, action: action)
    }

    private func openAttachmentIfAvailable(_ attachment: TranscriptAttachmentViewData, action: AttachmentAction) -> Bool {
        switch action {
        case .open:
            return openAttachmentForViewingIfAvailable(attachment)
        case .share:
            return presentShareSheetIfAvailable(for: attachment)
        }
    }

    private func openAttachmentForViewingIfAvailable(_ attachment: TranscriptAttachmentViewData) -> Bool {
        if attachment.kind == .image,
           let image = resolveImageForPresentation(from: attachment) {
            presentAttachment(
                .image(
                    AttachmentImagePresentation(
                        sourceAttachmentID: attachment.id,
                        title: attachment.title,
                        image: image,
                        shareURL: shareURLForImageAttachment(attachment)
                    )
                )
            )
            return true
        }

        if attachment.kind == .video,
           let videoURL = primaryContentURLForViewing(of: attachment) {
            presentAttachment(
                .video(
                    AttachmentVideoPresentation(
                        sourceAttachmentID: attachment.id,
                        title: attachment.title,
                        fileURL: videoURL,
                        shareURL: videoURL
                    )
                )
            )
            return true
        }

        guard let exportedURL = exportedURLForPrimaryContent(of: attachment) else {
            return false
        }

        switch attachment.primaryTapAffordance {
        case .imageViewer:
            return false
        case .videoViewer:
            return false
        case .quickLook:
            presentAttachment(
                .quickLook(
                    AttachmentFilePresentation(
                        title: attachment.title,
                        fileURL: exportedURL
                    )
                )
            )
        case .share:
            AttachmentSharePresenter.present(url: exportedURL)
        }
        return true
    }

    private func presentShareSheetIfAvailable(for attachment: TranscriptAttachmentViewData) -> Bool {
        if let localURL = resolvedLocalFileURL(for: attachment) {
            AttachmentSharePresenter.present(url: localURL)
            return true
        }
        guard let exportedURL = exportedURLForSharing(of: attachment) else {
            return false
        }
        AttachmentSharePresenter.present(url: exportedURL)
        return true
    }

    private func resumePendingAttachmentActionIfPossible() {
        guard let pending = pendingAttachmentAction else { return }

        switch attachmentDownloadManager.state(for: pending.objectKey) {
        case .loaded:
            pendingAttachmentAction = nil
            if !openAttachmentIfAvailable(pending.attachment, action: pending.action) {
                viewModel.errorMessage = attachmentFailureMessage(for: pending.attachment, action: pending.action)
            }
        case .failed:
            viewModel.errorMessage = attachmentFailureMessage(for: pending.attachment, action: pending.action)
            pendingAttachmentAction = nil
        case .loading, nil:
            break
        }
    }

    private var pendingAttachmentActionStateToken: String {
        guard let pending = pendingAttachmentAction else { return "idle" }
        switch attachmentDownloadManager.state(for: pending.objectKey) {
        case .none:
            return "\(pending.id)-idle"
        case .loading:
            return "\(pending.id)-loading"
        case .loaded:
            return "\(pending.id)-loaded"
        case .failed(let message):
            return "\(pending.id)-failed-\(message)"
        }
    }

    private var busyAttachmentID: String? {
        guard let pending = pendingAttachmentAction else { return nil }
        if case .loading = attachmentDownloadManager.state(for: pending.objectKey) {
            return pending.attachment.id
        }
        return nil
    }

    private var presentedAttachmentSourceID: String? {
        switch presentedAttachment {
        case .image(let presentation):
            return presentation.sourceAttachmentID
        case .video(let presentation):
            return presentation.sourceAttachmentID
        case .quickLook, .none:
            return nil
        }
    }

    private func resolveImageForPresentation(from attachment: TranscriptAttachmentViewData) -> UIImage? {
        if let previewKey = attachment.previewObjectKey,
           let image = attachmentDownloadManager.cachedImage(for: previewKey) {
            return image
        }
        if let image = attachmentDownloadManager.cachedImage(for: attachment.objectKey) {
            return image
        }
        if let localURL = resolvedLocalFileURL(for: attachment) {
            return UIImage(contentsOfFile: localURL.path)
        }
        return nil
    }

    private func shareURLForImageAttachment(_ attachment: TranscriptAttachmentViewData) -> URL? {
        if let localURL = resolvedLocalFileURL(for: attachment) {
            return localURL
        }
        return attachmentDownloadManager.exportToTempFile(
            objectKey: attachment.objectKey,
            fileName: preferredExportFileName(for: attachment, fallbackObjectKey: attachment.objectKey)
        )
    }

    private func exportedURLForPrimaryContent(of attachment: TranscriptAttachmentViewData) -> URL? {
        let objectKey = requiredDownloadObjectKey(for: attachment, action: .open)
        return attachmentDownloadManager.exportToTempFile(
            objectKey: objectKey,
            fileName: preferredExportFileName(for: attachment, fallbackObjectKey: objectKey)
        )
    }

    private func exportedURLForSharing(of attachment: TranscriptAttachmentViewData) -> URL? {
        let objectKey = requiredDownloadObjectKey(for: attachment, action: .share)
        return attachmentDownloadManager.exportToTempFile(
            objectKey: objectKey,
            fileName: preferredExportFileName(for: attachment, fallbackObjectKey: objectKey)
        )
    }

    private func primaryContentURLForViewing(of attachment: TranscriptAttachmentViewData) -> URL? {
        if let localURL = resolvedLocalFileURL(for: attachment) {
            return localURL
        }
        return exportedURLForPrimaryContent(of: attachment)
    }

    private func requiredDownloadObjectKey(for attachment: TranscriptAttachmentViewData, action: AttachmentAction) -> String {
        switch attachment.kind {
        case .image:
            switch action {
            case .open:
                return attachment.previewObjectKey ?? attachment.objectKey
            case .share:
                return attachment.objectKey
            }
        case .video, .audio, .file, .unknown:
            return attachment.objectKey
        }
    }

    private func preferredExportFileName(for attachment: TranscriptAttachmentViewData, fallbackObjectKey: String) -> String {
        let fallbackName = fallbackObjectKey.components(separatedBy: "/").last ?? "attachment"
        let trimmedTitle = attachment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return fallbackName }
        if (trimmedTitle as NSString).pathExtension.isEmpty {
            let fallbackExtension = (fallbackName as NSString).pathExtension
            if !fallbackExtension.isEmpty {
                return "\(trimmedTitle).\(fallbackExtension)"
            }
        }
        return trimmedTitle
    }

    private func attachmentFailureMessage(for attachment: TranscriptAttachmentViewData, action: AttachmentAction) -> String {
        let title = attachment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = String(localized: "this attachment")
        let resolvedTitle = title.isEmpty ? fallbackTitle : title

        switch action {
        case .open:
            return String.localizedStringWithFormat(String(localized: "Could not open %@."), resolvedTitle)
        case .share:
            return String.localizedStringWithFormat(String(localized: "Could not share %@."), resolvedTitle)
        }
    }

    private func resolvedLocalFileURL(for attachment: TranscriptAttachmentViewData) -> URL? {
        guard let localPath = attachment.localCacheURL, !localPath.isEmpty else { return nil }
        let fileURL: URL?
        if localPath.hasPrefix("file://") {
            fileURL = URL(string: localPath)
        } else {
            fileURL = URL(fileURLWithPath: localPath)
        }

        guard let fileURL else { return nil }
        let standardizedURL = fileURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            return nil
        }
        return standardizedURL
    }

    private func presentAttachment(_ attachment: PresentedAttachment) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            presentedAttachment = attachment
        }
    }

    private func dismissPresentedAttachment() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            presentedAttachment = nil
        }
    }

    private func showSaveConfirmation() {
        saveConfirmationMessage = String(localized: "Saved to Photos")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if saveConfirmationMessage != nil {
                saveConfirmationMessage = nil
            }
        }
    }

}

private enum AttachmentDownloadBootstrap {
    static func configureIfNeeded(environment: AppEnvironment) {
        AttachmentDownloadManager.defaultEnvironment = environment
    }
}

private enum AttachmentAction {
    case open
    case share
}

private struct PendingAttachmentAction: Identifiable {
    let id = UUID()
    let attachment: TranscriptAttachmentViewData
    let action: AttachmentAction
    let objectKey: String
}

private enum PresentedAttachment: Identifiable {
    case image(AttachmentImagePresentation)
    case video(AttachmentVideoPresentation)
    case quickLook(AttachmentFilePresentation)

    var id: UUID {
        switch self {
        case .image(let presentation):
            return presentation.id
        case .video(let presentation):
            return presentation.id
        case .quickLook(let presentation):
            return presentation.id
        }
    }
}

private struct AttachmentImagePresentation {
    let id = UUID()
    let sourceAttachmentID: String
    let title: String
    let image: UIImage
    let shareURL: URL?
}

private struct AttachmentFilePresentation {
    let id = UUID()
    let title: String
    let fileURL: URL
}

private struct AttachmentVideoPresentation {
    let id = UUID()
    let sourceAttachmentID: String
    let title: String
    let fileURL: URL
    let shareURL: URL
}

private struct AttachmentViewerScreen: View {
    let attachment: PresentedAttachment
    let transitionNamespace: Namespace.ID
    let onShare: (URL) -> Void
    let onSave: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())

            switch attachment {
            case .image(let presentation):
                AttachmentImageViewer(presentation: presentation, transitionNamespace: transitionNamespace, onShare: onShare, onSave: onSave, onDismiss: onDismiss)
            case .video(let presentation):
                AttachmentVideoViewer(presentation: presentation, transitionNamespace: transitionNamespace, onShare: onShare, onSave: onSave, onDismiss: onDismiss)
            case .quickLook(let presentation):
                AttachmentQuickLookViewer(presentation: presentation, onShare: onShare, onDismiss: onDismiss)
            }
        }
        .allowsHitTesting(true)
    }
}

private struct AttachmentImageViewer: View {
    let presentation: AttachmentImagePresentation
    let transitionNamespace: Namespace.ID
    let onShare: (URL) -> Void
    let onSave: (URL) -> Void
    let onDismiss: () -> Void
    @State private var dragOffsetY: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            let dragProgress = min(abs(dragOffsetY) / max(geometry.size.height * 0.45, 1), 1)

            ZStack {
                centeredMediaFrame(in: geometry) {
                    ZoomableImageView(image: presentation.image)
                        .matchedGeometryEffect(id: attachmentTransitionID(for: presentation.sourceAttachmentID), in: transitionNamespace)
                }
                .scaleEffect(1 - (dragProgress * 0.08))
                .offset(y: dragOffsetY)
                .simultaneousGesture(dismissDragGesture(containerHeight: geometry.size.height))

                VStack(spacing: 0) {
                    AttachmentViewerHeader(
                        safeAreaTop: safeArea.top,
                        trailingActions: presentation.shareURL.map { shareURL in
                            [
                                .init(icon: "square.and.arrow.up", label: String(localized: "Share")) {
                                    onShare(shareURL)
                                },
                                .init(icon: "square.and.arrow.down", label: String(localized: "Save")) {
                                    onSave(shareURL)
                                }
                            ]
                        } ?? [],
                        onDismiss: onDismiss
                    )

                    Spacer(minLength: 0)
                }
                .opacity(1 - dragProgress)
            }
        }
    }

    private func dismissDragGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffsetY = value.translation.height
            }
            .onEnded { value in
                let shouldDismiss = abs(value.translation.height) > containerHeight * 0.14
                if shouldDismiss {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        dragOffsetY = 0
                    }
                }
            }
    }
}

private struct AttachmentVideoViewer: View {
    let presentation: AttachmentVideoPresentation
    let transitionNamespace: Namespace.ID
    let onShare: (URL) -> Void
    let onSave: (URL) -> Void
    let onDismiss: () -> Void
    @State private var dragOffsetY: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            let dragProgress = min(abs(dragOffsetY) / max(geometry.size.height * 0.45, 1), 1)

            ZStack {
                centeredMediaFrame(in: geometry) {
                    VideoPlaybackSurface(url: presentation.fileURL)
                }
                .scaleEffect(1 - (dragProgress * 0.08))
                .offset(y: dragOffsetY)
                .simultaneousGesture(dismissDragGesture(containerHeight: geometry.size.height))

                VStack(spacing: 0) {
                    AttachmentViewerHeader(
                        safeAreaTop: safeArea.top,
                        trailingActions: [
                            .init(icon: "square.and.arrow.up", label: String(localized: "Share")) {
                                onShare(presentation.shareURL)
                            },
                            .init(icon: "square.and.arrow.down", label: String(localized: "Save")) {
                                onSave(presentation.shareURL)
                            }
                        ],
                        onDismiss: onDismiss
                    )

                    Spacer(minLength: 0)
                }
                .opacity(1 - dragProgress)
            }
        }
    }

    private func dismissDragGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffsetY = value.translation.height
            }
            .onEnded { value in
                let shouldDismiss = abs(value.translation.height) > containerHeight * 0.14
                if shouldDismiss {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        dragOffsetY = 0
                    }
                }
            }
    }
}

private struct AttachmentQuickLookViewer: View {
    let presentation: AttachmentFilePresentation
    let onShare: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets

            ZStack(alignment: .top) {
                QuickLookPreviewScreen(item: presentation)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                AttachmentViewerHeader(
                    safeAreaTop: safeArea.top,
                    trailingActions: [
                        .init(icon: "square.and.arrow.up", label: String(localized: "Share")) {
                            onShare(presentation.fileURL)
                        }
                    ],
                    onDismiss: onDismiss
                )
            }
        }
    }
}

private struct AttachmentViewerAction {
    let icon: String
    let label: String
    let action: () -> Void
}

private struct AttachmentViewerHeader: View {
    let safeAreaTop: CGFloat
    var trailingActions: [AttachmentViewerAction] = []
    let onDismiss: () -> Void

    private let buttonSize: CGFloat = 42
    private let iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Color.black.opacity(0.32), in: Circle())
            }

            Spacer()

            ForEach(Array(trailingActions.enumerated()), id: \.offset) { _, item in
                Button(action: item.action) {
                    Image(systemName: item.icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.black.opacity(0.32), in: Circle())
                }
                .accessibilityLabel(item.label)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

@ViewBuilder
private func centeredMediaFrame<Content: View>(in geometry: GeometryProxy, @ViewBuilder content: () -> Content) -> some View {
    content()
        .frame(
            maxWidth: geometry.size.width,
            maxHeight: geometry.size.height
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
}

private func attachmentTransitionID(for attachmentID: String) -> String {
    "attachment-transition-\(attachmentID)"
}

private struct QuickLookPreviewScreen: UIViewControllerRepresentable {
    let item: AttachmentFilePresentation

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.title = item.title
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.navigationBar.isHidden = true
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.item = item
        if let controller = uiViewController.viewControllers.first as? QLPreviewController {
            controller.reloadData()
            controller.title = item.title
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var item: AttachmentFilePresentation

        init(item: AttachmentFilePresentation) {
            self.item = item
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            item.fileURL as NSURL
        }
    }
}

private struct VideoPlaybackSurface: View {
    let url: URL
    @StateObject private var playbackModel: VideoPlaybackModel

    init(url: URL) {
        self.url = url
        _playbackModel = StateObject(wrappedValue: VideoPlaybackModel(url: url))
    }

    var body: some View {
        AspectFitPlayerView(player: playbackModel.player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .center) {
                if !playbackModel.isPlaying {
                    Button(action: playbackModel.togglePlayback) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 74, height: 74)
                            .background(Color.black.opacity(0.42), in: Circle())
                    }
                }
            }
            .overlay(alignment: .bottom) {
                compactPlaybackOverlay
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        .onAppear {
            playbackModel.startPlayback()
        }
        .onDisappear {
            playbackModel.stopPlayback()
        }
    }

    private var compactPlaybackOverlay: some View {
        HStack(spacing: 10) {
            Button(action: playbackModel.togglePlayback) {
                Image(systemName: playbackModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Slider(
                value: Binding(
                    get: { playbackModel.progress },
                    set: { playbackModel.seek(toProgress: $0) }
                ),
                in: 0...1
            )
            .tint(.white)
            .controlSize(.mini)
            .disabled(playbackModel.duration <= 0)

            Text(playbackModel.currentTimeLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.86))

            Text("/")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))

            Text(playbackModel.durationLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum AttachmentSharePresenter {
    static func present(url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            if url.path.contains("/clawchat-exports/") {
                try? FileManager.default.removeItem(at: url)
            }
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow),
              let presenter = topViewController(from: window.rootViewController) else {
            return
        }

        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }

    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}

private enum AttachmentSavePresenter {
    static func save(url: URL, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        let standardizedURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            complete(.failure(AttachmentSaveError.missingFile), completion: completion)
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                complete(.failure(AttachmentSaveError.permissionDenied), completion: completion)
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let creationDate = Date()
                if let type = mediaType(for: standardizedURL), type.conforms(to: .movie) {
                    if let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: standardizedURL) {
                        request.creationDate = creationDate
                    }
                } else if let type = mediaType(for: standardizedURL), type.conforms(to: .image) {
                    if let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: standardizedURL) {
                        request.creationDate = creationDate
                    }
                } else {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = creationDate
                    request.addResource(with: .photo, fileURL: standardizedURL, options: nil)
                }
            } completionHandler: { success, error in
                if let error {
                    complete(.failure(error), completion: completion)
                } else if success {
                    complete(.success(()), completion: completion)
                } else {
                    complete(.failure(AttachmentSaveError.unknownFailure), completion: completion)
                }
            }
        }
    }

    private static func mediaType(for url: URL) -> UTType? {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType
        }
        let pathExtension = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pathExtension.isEmpty else { return nil }
        return UTType(filenameExtension: pathExtension)
    }

    private static func complete(
        _ result: Result<Void, Error>,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        Task { @MainActor in
            completion(result)
        }
    }
}

private enum AttachmentSaveError: LocalizedError {
    case missingFile
    case permissionDenied
    case unknownFailure

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return String(localized: "The attachment file is no longer available to save.")
        case .permissionDenied:
            return String(localized: "Photo Library access is required to save attachments.")
        case .unknownFailure:
            return String(localized: "The attachment could not be saved to Photos.")
        }
    }
}

private struct AttachmentSaveConfirmationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.78), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
    }
}

private struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                .clipped()
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1, min(lastScale * value, 6))
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    if scale > 1 {
                        scale = 1
                        lastScale = 1
                    } else {
                        scale = 2
                        lastScale = 2
                    }
                }
        }
    }
}

private struct AspectFitPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer backing layer")
        }
        return layer
    }
}

@MainActor
private final class VideoPlaybackModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init(url: URL) {
        self.player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var currentTimeLabel: String {
        Self.formatTime(currentTime)
    }

    var durationLabel: String {
        Self.formatTime(duration)
    }

    func startPlayback() {
        installObserversIfNeeded()
        player.play()
        isPlaying = true
    }

    func stopPlayback() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(toProgress progress: Double) {
        guard duration > 0 else { return }
        let targetTime = CMTime(seconds: duration * progress, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = duration * progress
    }

    private func installObserversIfNeeded() {
        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentTime = max(time.seconds.isFinite ? time.seconds : 0, 0)
                    if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                        self.duration = itemDuration
                    }
                    self.isPlaying = self.player.rate > 0
                }
            }
        }

        if endObserver == nil {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.player.seek(to: .zero)
                    self.player.pause()
                    self.currentTime = 0
                    self.isPlaying = false
                }
            }
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", remainingSeconds)
    }
}

#Preview {
    NavigationStack {
        ChatDetailView(viewModel: ChatDetailViewModel(environment: .makeDefault(), sessionID: SessionID(rawValue: "preview")))
    }
}
