import SwiftUI
import UIKit

struct TranscriptRows {
    @ViewBuilder
    static func dateSeparator(_ separator: TranscriptDateSeparatorViewData, style: ChatAppearanceStyle) -> some View {
        HStack {
            Spacer()
            Text(separator.title)
                .font(style.dateSeparatorFont)
                .foregroundStyle(AppTheme.dim)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppTheme.panelAlt)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.vertical, style.scaled(8))
    }

    @ViewBuilder
    static func bubbleRow(_ item: TranscriptItemViewData, style: ChatAppearanceStyle, approvalState: ApprovalCardState, transitionNamespace: Namespace.ID, selectedAttachmentID: String?, busyAttachmentID: String?, onAttachmentTap: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentShare: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentRetry: @escaping (TranscriptAttachmentViewData) -> Void, onApprovalDecision: @escaping (ApprovalDecision) -> Void) -> some View {
        let isUser = item.isFromUser
        let roleAccent = isUser ? AppTheme.blue : AppTheme.assistantAccent
        let bubbleBackground = bubbleBackground(for: item)
        let bubbleStroke = bubbleStroke(for: item, accent: roleAccent)
        let mutedText = isUser ? AppTheme.dim.opacity(0.92) : AppTheme.dim
        let contentFont = style.bodyFont(isUser: isUser)

        HStack(alignment: .bottom, spacing: style.scaled(10)) {
            if isUser { Spacer(minLength: style.scaled(54)) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: style.scaled(5)) {
                if item.showsHeader {
                    HStack(spacing: style.scaled(6)) {
                        if isUser {
                            Text(String(localized: "You"))
                                .font(style.metadataFont)
                                .foregroundStyle(roleAccent)
                        }
                        Text(item.timestampText)
                            .font(style.timestampFont)
                            .foregroundStyle(mutedText)
                    }
                    .padding(.horizontal, style.scaled(4))
                }

                VStack(alignment: isUser ? .trailing : .leading, spacing: style.transcriptBlockSpacing) {
                    if !item.text.isEmpty {
                        MarkdownishText(
                            text: item.text,
                            font: contentFont,
                            codeFont: style.codeFont,
                            style: style,
                            isUserMessage: isUser
                        )
                        .foregroundStyle(AppTheme.text)
                        .lineSpacing(style.lineSpacing(isUser: isUser))
                    }

                    if !item.attachments.isEmpty {
                        attachmentList(item.attachments, style: style, transitionNamespace: transitionNamespace, selectedAttachmentID: selectedAttachmentID, busyAttachmentID: busyAttachmentID, onAttachmentTap: onAttachmentTap, onAttachmentShare: onAttachmentShare, onAttachmentRetry: onAttachmentRetry)
                    }

                    if let approval = item.execApproval, !isUser {
                        ApprovalCardView(approval: approval, state: approvalState, style: style, onDecision: onApprovalDecision)
                    }
                }
                .padding(.horizontal, isUser ? style.scaled(14) : style.scaled(16))
                .padding(.vertical, isUser ? style.userBubbleVerticalPadding() : style.assistantBubbleVerticalPadding())
                .background(
                    RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                        .fill(bubbleBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                        .stroke(bubbleStroke, lineWidth: 1)
                )

                if isUser && item.showsDeliveryStatus {
                    outgoingStatusView(for: item, style: style)
                        .padding(.horizontal, style.scaled(6))
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: isUser ? style.userBubbleMaxWidth : style.assistantBubbleMaxWidth, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: style.sideSpacerWidth) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.top, style.headerTopPadding(showsHeader: item.showsHeader))
        .padding(.bottom, style.dividerBottomPadding(showsDivider: item.showsDivider))
    }

    @ViewBuilder
    static func terminalRow(_ item: TranscriptItemViewData, style: ChatAppearanceStyle, approvalState: ApprovalCardState, transitionNamespace: Namespace.ID, selectedAttachmentID: String?, busyAttachmentID: String?, onAttachmentTap: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentShare: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentRetry: @escaping (TranscriptAttachmentViewData) -> Void, onApprovalDecision: @escaping (ApprovalDecision) -> Void) -> some View {
        let isUser = item.isFromUser
        let roleColor = isUser ? AppTheme.blue : AppTheme.assistantAccent
        let topPadding = terminalTopPadding(for: item, style: style)
        let bottomPadding = terminalBottomPadding(for: item, style: style)

        VStack(alignment: .leading, spacing: style.transcriptBlockSpacing) {
            if item.showsHeader {
                HStack(spacing: style.scaled(8)) {
                    if isUser {
                        Text(String(localized: "You"))
                            .font(style.metadataFont)
                            .foregroundStyle(roleColor)
                        Text(item.timestampText)
                            .font(style.timestampFont)
                            .foregroundStyle(AppTheme.dim)
                    }
                    if isUser && item.showsDeliveryStatus {
                        outgoingStatusIcon(for: item, style: style)
                    }
                }
            }

            if !item.text.isEmpty {
                MarkdownishText(
                    text: item.text,
                    font: style.terminalBodyFont,
                    codeFont: style.codeFont,
                    style: style,
                    isUserMessage: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(AppTheme.text)
                .lineSpacing(style.lineSpacing(isUser: false))
            }

            if !item.attachments.isEmpty {
                attachmentList(item.attachments, style: style, transitionNamespace: transitionNamespace, selectedAttachmentID: selectedAttachmentID, busyAttachmentID: busyAttachmentID, onAttachmentTap: onAttachmentTap, onAttachmentShare: onAttachmentShare, onAttachmentRetry: onAttachmentRetry)
            }

            if let approval = item.execApproval, !isUser {
                ApprovalCardView(approval: approval, state: approvalState, style: style, onDecision: onApprovalDecision)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, style.scaled(8))
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding + (isUser ? style.scaled(3) : 0))
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(isUser ? AppTheme.blue.opacity(0.10) : Color.clear)
        )
    }

    @ViewBuilder
    static func streamingRow(_ item: StreamingTranscriptItemViewData, style: ChatAppearanceStyle) -> some View {
        if style.isTerminal {
            VStack(alignment: .leading, spacing: style.transcriptBlockSpacing) {
                HStack(spacing: style.scaled(8)) {
                    Text(item.timestampText)
                        .font(style.timestampFont)
                        .foregroundStyle(AppTheme.dim)
                }
                MarkdownishText(
                    text: item.text,
                    font: style.terminalBodyFont,
                    codeFont: style.codeFont,
                    style: style,
                    isUserMessage: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(AppTheme.text)
                .lineSpacing(style.lineSpacing(isUser: false))
                StreamingStatusView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, style.scaled(8))
            .padding(.vertical, style.scaled(10))
        } else {
            HStack {
                VStack(alignment: .leading, spacing: style.scaled(5)) {
                    HStack(spacing: style.scaled(6)) {
                        Text(item.timestampText)
                            .font(style.timestampFont)
                            .foregroundStyle(AppTheme.dim)
                    }
                    VStack(alignment: .leading, spacing: style.transcriptBlockSpacing) {
                        MarkdownishText(
                            text: item.text,
                            font: style.bodyFont(isUser: false),
                            codeFont: style.codeFont,
                            style: style,
                            isUserMessage: false
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(AppTheme.text)
                        .lineSpacing(style.lineSpacing(isUser: false))

                        StreamingStatusView()
                    }
                    .padding(.horizontal, style.scaled(16))
                    .padding(.vertical, style.assistantBubbleVerticalPadding())
                    .background(
                        RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                            .fill(AppTheme.panelAlt)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: style.bubbleCornerRadius)
                            .stroke(AppTheme.assistantAccent.opacity(0.15), lineWidth: 1)
                    )
                }
                .frame(maxWidth: style.assistantStreamingMaxWidth, alignment: .leading)
                Spacer(minLength: style.sideSpacerWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, style.scaled(10))
        }
    }

    @ViewBuilder
    private static func attachmentList(_ attachments: [TranscriptAttachmentViewData], style: ChatAppearanceStyle, transitionNamespace: Namespace.ID, selectedAttachmentID: String?, busyAttachmentID: String?, onAttachmentTap: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentShare: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentRetry: @escaping (TranscriptAttachmentViewData) -> Void) -> some View {
        let images = attachments.filter { $0.kind == .image }
        let nonImages = attachments.filter { $0.kind != .image }

        VStack(alignment: .leading, spacing: style.scaled(8)) {
            if !images.isEmpty {
                imageGrid(images, style: style, transitionNamespace: transitionNamespace, selectedAttachmentID: selectedAttachmentID, busyAttachmentID: busyAttachmentID, onAttachmentTap: onAttachmentTap, onAttachmentShare: onAttachmentShare, onAttachmentRetry: onAttachmentRetry)
            }

            ForEach(nonImages) { attachment in
                Button {
                    onAttachmentTap(attachment)
                } label: {
                    fileRow(
                        attachment,
                        style: style,
                        tapAffordance: attachment.primaryTapAffordance,
                        isBusy: busyAttachmentID == attachment.id
                    )
                }
                .matchedGeometryEffect(id: attachmentTransitionID(for: attachment), in: transitionNamespace)
                .opacity(selectedAttachmentID == attachment.id && attachment.kind == .video ? 0.001 : 1)
                .buttonStyle(.plain)
                .disabled(busyAttachmentID == attachment.id)
                .contextMenu {
                    Button {
                        onAttachmentTap(attachment)
                    } label: {
                        Label(String(localized: "Open"), systemImage: attachment.primaryTapAffordance.symbolName)
                    }

                    Button {
                        onAttachmentShare(attachment)
                    } label: {
                        Label(String(localized: "Share or Save"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private static func imageGrid(_ attachments: [TranscriptAttachmentViewData], style: ChatAppearanceStyle, transitionNamespace: Namespace.ID, selectedAttachmentID: String?, busyAttachmentID: String?, onAttachmentTap: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentShare: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentRetry: @escaping (TranscriptAttachmentViewData) -> Void) -> some View {
        let columns = attachments.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: style.scaled(6)), GridItem(.flexible(), spacing: style.scaled(6))]

        LazyVGrid(columns: columns, spacing: style.scaled(6)) {
            ForEach(attachments) { attachment in
                imageTile(
                    attachment,
                    style: style,
                    transitionNamespace: transitionNamespace,
                    isSelected: selectedAttachmentID == attachment.id,
                    isBusy: busyAttachmentID == attachment.id,
                    onAttachmentTap: onAttachmentTap,
                    onAttachmentShare: onAttachmentShare,
                    onAttachmentRetry: onAttachmentRetry
                )
            }
        }
    }

    @ViewBuilder
    private static func imageTile(_ attachment: TranscriptAttachmentViewData, style: ChatAppearanceStyle, transitionNamespace: Namespace.ID, isSelected: Bool, isBusy: Bool, onAttachmentTap: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentShare: @escaping (TranscriptAttachmentViewData) -> Void, onAttachmentRetry: @escaping (TranscriptAttachmentViewData) -> Void) -> some View {
        let cell = AttachmentImageCell(
            attachment: attachment,
            style: style,
            isBusy: isBusy,
            onRetry: attachment.transferState == .failed ? { onAttachmentRetry(attachment) } : nil
        )
        .contentShape(Rectangle())
        .matchedGeometryEffect(id: attachmentTransitionID(for: attachment), in: transitionNamespace)
        .opacity(isSelected ? 0.001 : 1)

        Group {
            if attachment.transferState == .failed {
                cell
            } else {
                Button {
                    onAttachmentTap(attachment)
                } label: {
                    cell
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .contextMenu {
            if attachment.transferState != .failed {
                Button {
                    onAttachmentTap(attachment)
                } label: {
                    Label(String(localized: "Open"), systemImage: attachment.primaryTapAffordance.symbolName)
                }
            }

            Button {
                onAttachmentShare(attachment)
            } label: {
                Label(String(localized: "Share or Save"), systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private static func fileRow(_ attachment: TranscriptAttachmentViewData, style: ChatAppearanceStyle, tapAffordance: AttachmentTapAffordance, isBusy: Bool) -> some View {
        HStack(alignment: .center, spacing: style.scaled(10)) {
            Image(systemName: attachmentSymbol(for: attachment))
                .font(style.statusIconFont)
                .foregroundStyle(attachmentAccent(for: attachment))
                .frame(width: style.scaled(18))

            VStack(alignment: .leading, spacing: style.scaled(2)) {
                Text(attachment.title)
                    .font(style.bodyFont(isUser: attachment.isFromUser).weight(.medium))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
                if let detail = attachment.detail, !detail.isEmpty {
                    Text(detail)
                        .font(style.statusFont)
                        .foregroundStyle(AppTheme.dim)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            attachmentAccessory(style: style, tapAffordance: tapAffordance, isBusy: isBusy)
        }
        .padding(.horizontal, style.scaled(12))
        .padding(.vertical, style.scaled(10))
        .background(
            RoundedRectangle(cornerRadius: style.scaled(12), style: .continuous)
                .fill(AppTheme.panelAlt.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.scaled(12), style: .continuous)
                .stroke(AppTheme.border.opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private static func attachmentAccessory(style: ChatAppearanceStyle, tapAffordance: AttachmentTapAffordance, isBusy: Bool) -> some View {
        if isBusy {
            HStack(spacing: 0) {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.blue)
            }
        } else {
            Image(systemName: tapAffordance.symbolName)
                .font(.system(size: style.scaled(18), weight: .semibold))
                .foregroundStyle(AppTheme.dim)
                .accessibilityLabel(tapAffordance.accessibilityLabel)
        }
    }

    private static func attachmentTransitionID(for attachment: TranscriptAttachmentViewData) -> String {
        "attachment-transition-\(attachment.id)"
    }

    @ViewBuilder
    private static func outgoingStatusView(for item: TranscriptItemViewData, style: ChatAppearanceStyle) -> some View {
        if let failure = conciseFailureText(from: item) {
            HStack(spacing: style.scaled(4)) {
                outgoingStatusIcon(for: item, style: style)
                Text(failure)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(style.statusFont)
            }
            .foregroundStyle(AppTheme.red)
        } else if item.showsDeliveryStatus {
            outgoingStatusIcon(for: item, style: style)
        }
    }

    @ViewBuilder
    private static func outgoingStatusIcon(for item: TranscriptItemViewData, style: ChatAppearanceStyle) -> some View {
        Image(systemName: statusSymbol(for: item))
            .font(style.statusIconFont)
            .foregroundStyle(statusColor(for: item))
    }

    private static func statusSymbol(for item: TranscriptItemViewData) -> String {
        switch item.style {
        case .userFailed:
            return "exclamationmark.circle.fill"
        case .userConfirmed:
            return "envelope.open.fill"
        case .userSentToRelay:
            return "envelope.fill"
        case .userSending:
            return "clock"
        case .assistant:
            return "circle"
        }
    }

    private static func statusColor(for item: TranscriptItemViewData) -> Color {
        switch item.style {
        case .userFailed:
            return AppTheme.red
        case .userConfirmed:
            return AppTheme.blue
        case .userSentToRelay:
            return AppTheme.blue
        case .userSending:
            return AppTheme.dim
        case .assistant:
            return AppTheme.dim.opacity(0.18)
        }
    }

    private static func conciseFailureText(from item: TranscriptItemViewData) -> String? {
        guard case .userFailed(let reason) = item.style, let reason, !reason.isEmpty else { return nil }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("offline") { return String(localized: "Offline") }
        if trimmed.localizedCaseInsensitiveContains("timed out") || trimmed.localizedCaseInsensitiveContains("timeout") { return String(localized: "Timed out") }
        if trimmed.localizedCaseInsensitiveContains("unauthorized") || trimmed.localizedCaseInsensitiveContains("forbidden") { return String(localized: "Auth failed") }
        if trimmed.localizedCaseInsensitiveContains("could not connect") || trimmed.localizedCaseInsensitiveContains("cannot connect") { return String(localized: "Connect failed") }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let firstSentence = firstLine.components(separatedBy: ". ").first ?? firstLine
        return firstSentence.count > 48 ? String(firstSentence.prefix(48)) + "…" : firstSentence
    }

    private static func attachmentSymbol(for attachment: TranscriptAttachmentViewData) -> String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .video:
            return "video"
        case .audio:
            return "waveform"
        case .file, .unknown:
            switch attachment.transferState {
            case .failed:
                return "exclamationmark.triangle"
            case .pending:
                return "arrow.up.circle"
            case .uploaded, .available:
                return "paperclip"
            }
        }
    }

    private static func attachmentAccent(for attachment: TranscriptAttachmentViewData) -> Color {
        switch attachment.transferState {
        case .failed:
            return AppTheme.red
        case .pending:
            return AppTheme.blue
        case .uploaded, .available:
            switch attachment.kind {
            case .image, .video:
                return AppTheme.blue
            case .audio:
                return AppTheme.assistantAccent
            case .file, .unknown:
                return AppTheme.dim
            }
        }
    }

    private static func terminalTopPadding(for item: TranscriptItemViewData, style: ChatAppearanceStyle) -> CGFloat {
        if !item.isFromUser && item.showsHeader {
            return style.scaled(4)
        }
        return style.scaled(10)
    }

    private static func terminalBottomPadding(for item: TranscriptItemViewData, style: ChatAppearanceStyle) -> CGFloat {
        if item.isFromUser && item.showsDivider {
            return style.scaled(4)
        }
        return style.scaled(10)
    }

    private static func bubbleBackground(for item: TranscriptItemViewData) -> Color {
        switch item.style {
        case .userFailed:
            return AppTheme.red.opacity(0.08)
        case .userSending:
            return Color.dynamic(
                light: UIColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1),
                dark: UIColor(red: 0.11, green: 0.20, blue: 0.29, alpha: 0.48)
            )
        case .userSentToRelay, .userConfirmed:
            return Color.dynamic(
                light: UIColor(red: 0.87, green: 0.92, blue: 0.98, alpha: 1),
                dark: UIColor(red: 0.10, green: 0.19, blue: 0.28, alpha: 0.62)
            )
        case .assistant:
            return Color.dynamic(
                light: UIColor(red: 0.985, green: 0.982, blue: 0.975, alpha: 1),
                dark: UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1)
            )
        }
    }

    private static func bubbleStroke(for item: TranscriptItemViewData, accent: Color) -> Color {
        switch item.style {
        case .userFailed, .userSending, .userSentToRelay, .userConfirmed:
            return AppTheme.blue.opacity(0.05)
        case .assistant:
            return accent.opacity(0.05)
        }
    }
}

private struct ApprovalCardView: View {
    let approval: ExecApprovalMetadata
    let state: ApprovalCardState
    let style: ChatAppearanceStyle
    let onDecision: (ApprovalDecision) -> Void

    private var decisions: [ApprovalDecision] {
        approval.allowedDecisions.compactMap(ApprovalDecision.init(rawValue:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.scaled(10)) {
            VStack(alignment: .leading, spacing: style.scaled(4)) {
                Text(String(localized: "Approval required"))
                    .font(style.metadataFont.weight(.semibold))
                    .foregroundStyle(AppTheme.assistantAccent)
                Text(approval.title)
                    .font(style.statusFont.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                if let body = approval.body, !body.isEmpty {
                    Text(body)
                        .font(style.statusFont)
                        .foregroundStyle(AppTheme.dim)
                } else {
                    Text(String(localized: "OpenClaw needs your approval before it can continue."))
                        .font(style.statusFont)
                        .foregroundStyle(AppTheme.dim)
                }
                Text(String.localizedStringWithFormat(String(localized: "Type: %@"), approval.approvalKind))
                    .font(style.statusFont)
                    .foregroundStyle(AppTheme.dim)
                Text(String.localizedStringWithFormat(String(localized: "Ref: %@"), approval.approvalID))
                    .font(style.timestampFont)
                    .foregroundStyle(AppTheme.dim.opacity(0.9))
            }

            switch state {
            case .pending:
                HStack(spacing: style.scaled(8)) {
                    ForEach(decisions, id: \.rawValue) { decision in
                        Button(action: { onDecision(decision) }) {
                            Text(label(for: decision))
                                .font(style.statusFont.weight(.semibold))
                                .padding(.horizontal, style.scaled(10))
                                .padding(.vertical, style.scaled(8))
                                .background(background(for: decision), in: Capsule())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                onDecision(decision)
                            }
                        )
                    }
                }
            case .sending(let decision):
                HStack(spacing: style.scaled(8)) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Sending approval…"))
                        .font(style.statusFont.weight(.semibold))
                        .foregroundStyle(AppTheme.dim)
                    Text(label(for: decision))
                        .font(style.timestampFont)
                        .foregroundStyle(AppTheme.assistantAccent)
                }
            case .resolved(let decision):
                Text(resolvedLabel(for: decision))
                    .font(style.statusFont.weight(.semibold))
                    .foregroundStyle(AppTheme.assistantAccent)
                    .padding(.horizontal, style.scaled(10))
                    .padding(.vertical, style.scaled(8))
                    .background(AppTheme.assistantAccent.opacity(0.12), in: Capsule())
            case .failed(let decision, let message):
                VStack(alignment: .leading, spacing: style.scaled(8)) {
                    Text(String(localized: "Failed to send approval."))
                        .font(style.statusFont.weight(.semibold))
                        .foregroundStyle(AppTheme.red)
                    Text(message)
                        .font(style.timestampFont)
                        .foregroundStyle(AppTheme.dim)
                    Button(action: { onDecision(decision) }) {
                        Text(String(localized: "Try again"))
                            .font(style.statusFont.weight(.semibold))
                            .padding(.horizontal, style.scaled(10))
                            .padding(.vertical, style.scaled(8))
                            .background(AppTheme.red.opacity(0.12), in: Capsule())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            onDecision(decision)
                        }
                    )
                }
            }
        }
        .padding(style.scaled(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: style.scaled(10), style: .continuous)
                .fill(AppTheme.panelAlt.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: style.scaled(10), style: .continuous)
                .stroke(AppTheme.border.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private func label(for decision: ApprovalDecision) -> String {
        switch decision {
        case .allowOnce:
            return String(localized: "Approve once")
        case .allowAlways:
            return String(localized: "Always allow")
        case .deny:
            return String(localized: "Deny")
        }
    }

    private func background(for decision: ApprovalDecision) -> Color {
        switch decision {
        case .allowOnce:
            return AppTheme.blue.opacity(0.14)
        case .allowAlways:
            return AppTheme.assistantAccent.opacity(0.16)
        case .deny:
            return AppTheme.red.opacity(0.14)
        }
    }

    private func resolvedLabel(for decision: ApprovalDecision) -> String {
        switch decision {
        case .allowOnce:
            return String(localized: "Approved once")
        case .allowAlways:
            return String(localized: "Always allow sent")
        case .deny:
            return String(localized: "Denied")
        }
    }
}

struct AttachmentImageCell: View {
    let attachment: TranscriptAttachmentViewData
    let style: ChatAppearanceStyle
    let isBusy: Bool
    let onRetry: (() -> Void)?
    @State private var downloadManager = AttachmentDownloadManager.shared

    private var remoteKey: String {
        attachment.previewObjectKey ?? attachment.objectKey
    }

    private var resolvedImage: UIImage? {
        // Always try the remote key first (covers both local-seeded and remote-downloaded cases)
        if let img = downloadManager.cachedImage(for: remoteKey) { return img }
        // Fallback: read local file directly (first render before seeding has run)
        if let url = existingLocalFileURL {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    private var existingLocalFileURL: URL? {
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

    private var isUploading: Bool { attachment.transferState == .pending }
    private var canRetry: Bool { attachment.transferState == .failed && onRetry != nil }

    var body: some View {
        ZStack(alignment: .center) {
            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minHeight: style.scaled(100), maxHeight: style.scaled(260))
                    .clipShape(RoundedRectangle(cornerRadius: style.scaled(12), style: .continuous))
                    .overlay(alignment: .center) {
                        if isUploading {
                            ZStack {
                                RoundedRectangle(cornerRadius: style.scaled(12), style: .continuous)
                                    .fill(Color.black.opacity(0.30))
                                UploadProgressRing(size: style.scaled(36))
                            }
                            .transition(.opacity)
                        } else if isBusy {
                            AttachmentLoadingOverlay(style: style)
                        } else if canRetry {
                            retryOverlay
                        }
                    }
            } else if case .loading = downloadManager.state(for: remoteKey) {
                imagePlaceholder(style: style)
                    .overlay { ProgressView().tint(AppTheme.dim) }
            } else if case .failed(let msg) = downloadManager.state(for: remoteKey) {
                imagePlaceholder(style: style, height: style.scaled(80))
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(AppTheme.red)
                            Text(msg).font(style.statusFont).foregroundStyle(AppTheme.dim).lineLimit(2)
                        }
                    }
            } else {
                imagePlaceholder(style: style)
                    .overlay {
                        if canRetry {
                            retryOverlay
                        } else {
                            Image(systemName: "photo").font(.title2).foregroundStyle(AppTheme.dim)
                        }
                    }
                    .onAppear {
                        guard attachment.transferState != .pending else { return }
                        downloadManager.ensureDownloaded(objectKey: remoteKey)
                    }
            }
        }
        .onAppear {
            // Seed cache from local file so image is instant even for older messages
            if let localURL = existingLocalFileURL {
                downloadManager.seedFromLocalFile(objectKey: remoteKey, localPath: localURL.path)
            }
        }
    }

    @ViewBuilder
    private func imagePlaceholder(style: ChatAppearanceStyle, height: CGFloat? = nil) -> some View {
        RoundedRectangle(cornerRadius: style.scaled(12), style: .continuous)
            .fill(AppTheme.panelAlt.opacity(0.5))
            .frame(height: height ?? style.scaled(120))
    }

    private var retryOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: style.scaled(12), style: .continuous)
                .fill(Color.black.opacity(0.34))

            Button(action: { onRetry?() }) {
                Label(String(localized: "Retry"), systemImage: "arrow.clockwise.circle.fill")
                    .font(style.statusFont.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, style.scaled(12))
                    .padding(.vertical, style.scaled(8))
                    .background(Color.black.opacity(0.28), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AttachmentLoadingOverlay: View {
    let style: ChatAppearanceStyle

    var body: some View {
        VStack(spacing: 0) {
            ProgressView()
                .controlSize(.regular)
                .tint(.white)
        }
        .padding(.horizontal, style.scaled(14))
        .padding(.vertical, style.scaled(12))
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: style.scaled(14), style: .continuous))
    }
}

/// Indefinite spinning ring shown over images during upload.
private struct UploadProgressRing: View {
    let size: CGFloat
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.10, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.3), radius: 2)
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
