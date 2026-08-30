import Foundation

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct TranscriptPresenter {
    func present(_ messages: [ChatMessage]) -> [TranscriptDisplayItem] {
        var result: [TranscriptDisplayItem] = []
        var previousRenderableMessage: ChatMessage?
        var activeStreamByID: [String: Int] = [:]
        var activeStreamTextByID: [String: String] = [:]
        var completedStreamIDs: Set<String> = []

        for (index, message) in messages.enumerated() {
            if shouldInsertDateSeparator(before: message, previous: previousRenderableMessage) {
                result.append(.dateSeparator(
                    TranscriptDateSeparatorViewData(
                        id: "date-\(dayKey(for: message.sentAt))",
                        title: dateSeparatorTitle(for: message.sentAt)
                    )
                ))
            }

            let isFromUser: Bool = {
                if case .user = message.sender { return true }
                return false
            }()

            if !isFromUser, case .partial(let streamID, _) = message.streamState {
                if completedStreamIDs.contains(streamID) {
                    previousRenderableMessage = message
                    continue
                }

                let item = StreamingTranscriptItemViewData(
                    id: "stream-\(streamID)",
                    text: message.text,
                    timestampText: timestampText(for: message.sentAt),
                    isTerminalStyle: false
                )
                if let existingIndex = activeStreamByID[streamID] {
                    result[existingIndex] = .streaming(item)
                } else {
                    activeStreamByID[streamID] = result.count
                    result.append(.streaming(item))
                }
                activeStreamTextByID[streamID] = message.text
                previousRenderableMessage = message
                continue
            }

            if !isFromUser, !isPartial(message) {
                let matchedStreamID = exactStreamID(for: message)
                    ?? inferMatchingStreamID(
                        for: message,
                        activeStreamByID: activeStreamByID,
                        activeStreamTextByID: activeStreamTextByID
                    )

                if let matchedStreamID {
                    removeActiveStream(
                        matchedStreamID,
                        from: &result,
                        activeStreamByID: &activeStreamByID,
                        activeStreamTextByID: &activeStreamTextByID
                    )
                    completedStreamIDs.insert(matchedStreamID)
                } else if message.isStreamComplete, let latestActiveStreamID = latestActiveStreamID(in: activeStreamByID) {
                    // Fallback: if backend marks completion without a stable stream ID, replace the newest partial stream.
                    removeActiveStream(
                        latestActiveStreamID,
                        from: &result,
                        activeStreamByID: &activeStreamByID,
                        activeStreamTextByID: &activeStreamTextByID
                    )
                    completedStreamIDs.insert(latestActiveStreamID)
                }
            }

            let style: TranscriptRowStyle = {
                guard isFromUser else { return .assistant }
                switch message.deliveryState {
                case .sending, .localOnly:
                    return .userSending
                case .sentToRelay:
                    return .userSentToRelay
                case .confirmed:
                    return .userConfirmed
                case .failed(let reason):
                    return .userFailed(reason)
                }
            }()

            let previousIsSameSender: Bool = {
                if isFromUser {
                    return false
                }
                guard let previousRenderableMessage else { return false }
                return sameSender(previousRenderableMessage, message) && Calendar.current.isDate(previousRenderableMessage.sentAt, inSameDayAs: message.sentAt)
            }()

            let nextMessage = index + 1 < messages.count ? messages[index + 1] : nil
            let showsDeliveryStatus = shouldShowDeliveryStatus(for: message, nextMessage: nextMessage)

            result.append(.message(
                TranscriptItemViewData(
                    id: message.id.rawValue,
                    text: message.text,
                    attachments: presentAttachments(message.attachments, messageID: message.id, isFromUser: isFromUser),
                    isFromUser: isFromUser,
                    timestampText: timestampText(for: message.sentAt),
                    style: style,
                    statusText: {
                        switch style {
                        case .userSending: return String(localized: "Sending…")
                        case .userSentToRelay: return String(localized: "Delivered to relay")
                        case .userConfirmed: return String(localized: "Confirmed")
                        case .userFailed(let reason): return reason ?? String(localized: "Failed")
                        case .assistant: return nil
                        }
                    }(),
                    showsHeader: !previousIsSameSender,
                    showsDivider: false,
                    showsDeliveryStatus: showsDeliveryStatus,
                    execApproval: message.execApproval,
                    execApprovalResolution: message.execApprovalResolution
                )
            ))

            previousRenderableMessage = message
        }

        return applyDividers(to: result)
    }

    private func shouldShowDeliveryStatus(for message: ChatMessage, nextMessage: ChatMessage?) -> Bool {
        guard case .user = message.sender else { return false }

        switch message.deliveryState {
        case .failed:
            return true
        case .sending, .localOnly, .sentToRelay, .confirmed:
            break
        }

        guard let nextMessage else { return true }
        guard case .assistant = nextMessage.sender else { return true }
        return false
    }

    private func applyDividers(to items: [TranscriptDisplayItem]) -> [TranscriptDisplayItem] {
        var updated = items

        for index in updated.indices {
            guard case .message(let current) = updated[index] else { continue }
            let nextMessage = nextMessageItem(after: index, in: updated)
            let shouldShowDivider: Bool = {
                guard let nextMessage else { return false }
                return current.isFromUser != nextMessage.isFromUser
            }()
            updated[index] = .message(
                TranscriptItemViewData(
                    id: current.id,
                    text: current.text,
                    attachments: current.attachments,
                    isFromUser: current.isFromUser,
                    timestampText: current.timestampText,
                    style: current.style,
                    statusText: current.statusText,
                    showsHeader: current.showsHeader,
                    showsDivider: shouldShowDivider,
                    showsDeliveryStatus: current.showsDeliveryStatus,
                    execApproval: current.execApproval,
                    execApprovalResolution: current.execApprovalResolution
                )
            )
        }

        return updated
    }

    private func nextMessageItem(after index: Int, in items: [TranscriptDisplayItem]) -> TranscriptItemViewData? {
        guard index + 1 < items.count else { return nil }
        for nextIndex in (index + 1)..<items.count {
            switch items[nextIndex] {
            case .message(let item):
                return item
            case .dateSeparator, .streaming:
                continue
            }
        }
        return nil
    }

    private func exactStreamID(for message: ChatMessage) -> String? {
        message.streamID
    }

    private func presentAttachments(_ attachments: [ChatAttachment], messageID: MessageID, isFromUser: Bool) -> [TranscriptAttachmentViewData] {
        attachments.map { attachment in
            TranscriptAttachmentViewData(
                id: attachment.id,
                messageID: messageID.rawValue,
                title: attachment.fileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? fallbackTitle(for: attachment.kind),
                detail: attachmentDetail(for: attachment),
                kind: attachment.kind,
                transferState: attachment.transferState,
                isFromUser: isFromUser,
                objectKey: attachment.objectKey,
                previewObjectKey: attachment.previewObjectKey,
                localCacheURL: attachment.localCacheURL,
                mimeType: attachment.mimeType,
                sizeBytes: attachment.sizeBytes,
                width: attachment.width,
                height: attachment.height
            )
        }
    }

    private func attachmentDetail(for attachment: ChatAttachment) -> String? {
        var parts: [String] = []
        if let mimeType = attachment.mimeType?.trimmingCharacters(in: .whitespacesAndNewlines), !mimeType.isEmpty {
            parts.append(mimeType)
        }
        if let sizeBytes = attachment.sizeBytes, sizeBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file))
        }
        switch attachment.transferState {
        case .pending:
            parts.append(String(localized: "Pending upload"))
        case .uploaded:
            parts.append(String(localized: "Uploaded"))
        case .available:
            break
        case .failed:
            parts.append(String(localized: "Transfer failed"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func fallbackTitle(for kind: AttachmentKind) -> String {
        switch kind {
        case .image:
            return String(localized: "Image")
        case .video:
            return String(localized: "Video")
        case .audio:
            return String(localized: "Audio")
        case .file, .unknown:
            return String(localized: "Attachment")
        }
    }

    private func isPartial(_ message: ChatMessage) -> Bool {
        if case .partial = message.streamState { return true }
        return false
    }

    private func inferMatchingStreamID(
        for message: ChatMessage,
        activeStreamByID: [String: Int],
        activeStreamTextByID: [String: String]
    ) -> String? {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scoredCandidates: [(streamID: String, score: Int)] = activeStreamTextByID.compactMap { streamID, partialText in
            let normalizedPartial = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPartial.isEmpty else { return nil }
            let isPrefixMatch = text.hasPrefix(normalizedPartial) || normalizedPartial.hasPrefix(text)
            guard isPrefixMatch else { return nil }
            return (streamID, normalizedPartial.count)
        }

        if let best = scoredCandidates.max(by: { lhs, rhs in
            if lhs.score == rhs.score {
                return (activeStreamByID[lhs.streamID] ?? -1) < (activeStreamByID[rhs.streamID] ?? -1)
            }
            return lhs.score < rhs.score
        }) {
            return best.streamID
        }

        if activeStreamByID.count == 1 {
            return activeStreamByID.keys.first
        }

        return nil
    }

    private func latestActiveStreamID(in activeStreamByID: [String: Int]) -> String? {
        activeStreamByID.max(by: { $0.value < $1.value })?.key
    }

    private func removeActiveStream(
        _ streamID: String,
        from result: inout [TranscriptDisplayItem],
        activeStreamByID: inout [String: Int],
        activeStreamTextByID: inout [String: String]
    ) {
        guard let streamingIndex = activeStreamByID[streamID] else { return }
        result.remove(at: streamingIndex)
        activeStreamByID.removeValue(forKey: streamID)
        activeStreamTextByID.removeValue(forKey: streamID)
        activeStreamByID = activeStreamByID.mapValues { index in
            index > streamingIndex ? index - 1 : index
        }
    }

    private func shouldInsertDateSeparator(before message: ChatMessage, previous: ChatMessage?) -> Bool {
        guard let previous else { return true }
        return !Calendar.current.isDate(previous.sentAt, inSameDayAs: message.sentAt)
    }

    private func dateSeparatorTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func dayKey(for date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }

    private func timestampText(for date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func sameSender(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        switch (lhs.sender, rhs.sender) {
        case (.user, .user), (.assistant, .assistant):
            return true
        default:
            return false
        }
    }
}

private extension ChatMessage {
    var isStreamComplete: Bool {
        if case .complete = streamState { return true }
        return false
    }
}
