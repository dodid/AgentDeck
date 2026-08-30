import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct ChatComposerView: View {
    let viewModel: ChatDetailViewModel
    let style: ChatAppearanceStyle
    @FocusState.Binding var inputFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if viewModel.isInteractionLocked {
                Button {
                    viewModel.requestComposerAccess()
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Text(viewModel.composerPlaceholder)
                            .font(style.composerFont)
                            .foregroundStyle(AppTheme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "lock.circle.fill")
                            .font(style.composerActionIconFont)
                            .foregroundStyle(AppTheme.blue)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: style.composerCornerRadius))
                    .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: -2)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    if !viewModel.draftAttachments.isEmpty {
                        composerAttachmentTray
                    }

                    HStack(alignment: .center, spacing: 10) {
                        attachmentButton

                        HStack(alignment: .center, spacing: 10) {
                            TextField(
                                viewModel.composerPlaceholder,
                                text: Binding(
                                    get: { viewModel.draftText },
                                    set: { viewModel.setDraftText($0) }
                                ),
                                axis: .vertical
                            )
                            .textFieldStyle(.plain)
                            .font(style.composerFont)
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(1...5)
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                            .focused($inputFocused)
                            .submitLabel(.return)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)

                            if viewModel.hasContent || viewModel.hasSuggestions {
                                Button(action: onSubmit) {
                                    Image(systemName: viewModel.hasSuggestions ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                                        .font(style.composerActionIconFont)
                                        .foregroundStyle(sendButtonDisabled ? AppTheme.dim.opacity(0.45) : AppTheme.blue)
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.plain)
                                .disabled(sendButtonDisabled)
                            } else {
                                Button {
                                    inputFocused = false
                                    viewModel.toggleDictation()
                                } label: {
                                    Image(systemName: viewModel.isDictating ? "waveform.circle.fill" : "mic.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(viewModel.isDictating ? AppTheme.red : AppTheme.blue)
                                        .frame(width: 30, height: 30)
                                        .background((viewModel.isDictating ? AppTheme.red.opacity(0.12) : AppTheme.blue.opacity(0.10)), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: viewModel.isDictating ? "Stop voice input" : "Start voice input"))
                            }
                        }
                        .padding(.leading, 14)
                        .padding(.trailing, 10)
                        .padding(.vertical, 10)
                        .frame(minHeight: 46, alignment: .center)
                        .background(AppTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: composerContainerCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: composerContainerCornerRadius, style: .continuous)
                                .stroke(viewModel.isDictating ? AppTheme.blue.opacity(0.35) : AppTheme.border.opacity(0.24), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: composerContainerCornerRadius, style: .continuous))
                        .onTapGesture {
                            inputFocused = true
                        }
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -2)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(AppTheme.bg)
    }

    private var composerAttachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.draftAttachments) { attachment in
                    DraftAttachmentThumbnail(
                        attachment: attachment,
                        onRemove: { viewModel.removeAttachment(attachment) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    private var attachmentButton: some View {
        PhotosPicker(
            selection: Binding(
                get: { viewModel.pendingPhotosPickerItems },
                set: {
                    viewModel.pendingPhotosPickerItems = $0
                    viewModel.handlePhotosPickerChange()
                }
            ),
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos])
        ) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
                .frame(width: 40, height: 40)
                .background(AppTheme.panel, in: Circle())
                .overlay(Circle().stroke(AppTheme.border.opacity(0.24), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: -1)
        }
        .buttonStyle(.plain)
    }

    private func attachmentIcon(for kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .file, .unknown: return "paperclip"
        }
    }

    private var sendButtonDisabled: Bool {
        viewModel.isSending || viewModel.isInteractionLocked || !viewModel.hasContent
    }

    private var composerContainerCornerRadius: CGFloat {
        viewModel.draftText.contains("\n") || viewModel.draftText.count > 32 ? 18 : 23
    }
}

private struct DraftAttachmentThumbnail: View {
    let attachment: DraftAttachment
    let onRemove: () -> Void
    @State private var thumbnail: UIImage?

    private let tileSize = CGSize(width: 54, height: 54)
    private let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailBody
                .frame(width: tileSize.width, height: tileSize.height)
                .background(AppTheme.panelAlt.opacity(0.78), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.border.opacity(0.28), lineWidth: 1)
                )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white, Color.black.opacity(0.55))
                    .background(Color.black.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .onAppear(perform: loadThumbnailIfNeeded)
    }

    @ViewBuilder
    private var thumbnailBody: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.panelAlt.opacity(0.92))

                Image(systemName: placeholderIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.blue)
            }
        }
    }

    private var placeholderIcon: String {
        switch attachment.kind {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .file, .unknown: return "paperclip"
        }
    }

    private func loadThumbnailIfNeeded() {
        guard thumbnail == nil,
              let localURL = attachment.localURL.map(URL.init(fileURLWithPath:)) else { return }

        switch attachment.kind {
        case .image:
            if let image = UIImage(contentsOfFile: localURL.path) {
                thumbnail = image
            }
        case .video:
            let asset = AVURLAsset(url: localURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: tileSize.width * 2, height: tileSize.height * 2)
            generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, error in
                guard error == nil, let cgImage else { return }
                Task { @MainActor in
                    thumbnail = UIImage(cgImage: cgImage)
                }
            }
        case .audio, .file, .unknown:
            break
        }
    }
}
