import SwiftUI
import UIKit

struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    var openConnectionEditor: (() -> Void)? = nil
    @State private var showAttachmentCleanupOptions = false

    var body: some View {
        List {
            Section {
                CopyableSettingRow(icon: "externaldrive.connected.to.line.below", title: "Bucket", value: viewModel.bucketSummary)
                CopyableSettingRow(icon: "network", title: "Endpoint", value: viewModel.endpointSummary)
                CopyableSettingRow(icon: "iphone", title: "Device", value: viewModel.deviceSummary.isEmpty ? String(localized: "Unknown") : viewModel.deviceSummary)
                MenuSettingRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Message fetching",
                    value: viewModel.messageFetchPreset.localizedLabel,
                    options: MessageFetchPreset.allCases.map { value in
                        MenuSettingOption(
                            title: value.localizedLabel,
                            isSelected: value == viewModel.messageFetchPreset,
                            action: { Task { await viewModel.updateMessageFetchPreset(value) } }
                        )
                    }
                )
            } header: {
                Text("Connection")
            }
            .listRowBackground(AppTheme.panel)

            Section("Appearance") {
                MenuSettingRow(
                    icon: "circle.lefthalf.filled",
                    title: "Theme",
                    value: viewModel.appearance.theme.localizedLabel,
                    options: AppThemePreference.allCases.map { value in
                        MenuSettingOption(
                            title: value.localizedLabel,
                            isSelected: value == viewModel.appearance.theme,
                            action: { Task { await viewModel.updateTheme(value) } }
                        )
                    }
                )

                MenuSettingRow(
                    icon: "rectangle.on.rectangle",
                    title: "Chat style",
                    value: viewModel.appearance.chatStyle.localizedLabel,
                    options: ChatStyle.allCases.map { value in
                        MenuSettingOption(
                            title: value.localizedLabel,
                            isSelected: value == viewModel.appearance.chatStyle,
                            action: { Task { await viewModel.updateChatStyle(value) } }
                        )
                    }
                )

                MenuSettingRow(
                    icon: "textformat.alt",
                    title: "Chat font",
                    value: viewModel.appearance.chatFont.localizedLabel,
                    options: ChatFontPreference.allCases.map { value in
                        MenuSettingOption(
                            title: value.localizedLabel,
                            isSelected: value == viewModel.appearance.chatFont,
                            action: { Task { await viewModel.updateChatFont(value) } }
                        )
                    }
                )

                MenuSettingRow(
                    icon: "textformat.size",
                    title: "Font size",
                    value: viewModel.appearance.fontSize.localizedLabel,
                    options: FontSizePreference.allCases.map { value in
                        MenuSettingOption(
                            title: value.localizedLabel,
                            isSelected: value == viewModel.appearance.fontSize,
                            action: { Task { await viewModel.updateFontSize(value) } }
                        )
                    }
                )
            }
            .listRowBackground(AppTheme.panel)

            Section("Actions") {
                Button {
                    openConnectionEditor?()
                } label: {
                    Label("Edit R2 config", systemImage: "slider.horizontal.3")
                        .font(AppTheme.font(.body, size: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(AppTheme.text)

                Button {
                    Task { await viewModel.refreshSessions() }
                } label: {
                    HStack {
                        Label("Refresh sessions", systemImage: "arrow.clockwise")
                            .font(AppTheme.font(.body, size: .medium))
                        Spacer()
                        if viewModel.isWorking {
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(AppTheme.text)
            }
            .listRowBackground(AppTheme.panel)

            Section("Storage") {
                StorageStatRow(icon: "paperclip.circle", title: "Attachment cache", value: attachmentStorageLabel)

                ActionSettingRow(
                    icon: "trash",
                    title: "Clean attachments",
                    action: { showAttachmentCleanupOptions = true }
                )
                .disabled(viewModel.isWorking)
            }
            .listRowBackground(AppTheme.panel)

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppTheme.red)
                }
                .listRowBackground(AppTheme.panel)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.bg)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .confirmationDialog(
            "Clean attachments",
            isPresented: $showAttachmentCleanupOptions,
            titleVisibility: .visible
        ) {
            Button("Older than 7 days", role: .destructive) {
                Task {
                    await viewModel.cleanupAttachmentData(olderThan: .sevenDays)
                }
            }
            Button("Clean all", role: .destructive) {
                Task {
                    await viewModel.cleanupAllAttachmentData()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Cleanup Complete",
            isPresented: Binding(
                get: { viewModel.cleanupResultMessage != nil },
                set: { if !$0 { viewModel.cleanupResultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.cleanupResultMessage = nil
            }
        } message: {
            Text(viewModel.cleanupResultMessage ?? "")
        }
    }

    private var attachmentStorageLabel: String {
        fileSizeLabel(viewModel.storageStats.attachmentDataSizeBytes)
    }

    private func fileSizeLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct StorageStatRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(AppTheme.blue)
            Text(title)
                .foregroundStyle(AppTheme.dim)
                .font(AppTheme.font(.body, size: .medium))
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(AppTheme.text)
                .font(AppTheme.font(.body, size: .medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

private struct ActionSettingRow: View {
    let icon: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(AppTheme.blue)
                Text(title)
                    .foregroundStyle(AppTheme.dim)
                    .font(AppTheme.font(.body, size: .medium))
                Spacer(minLength: 12)
                Image(systemName: "ellipsis.circle")
                    .font(AppTheme.font(.body, size: .medium))
                    .foregroundStyle(AppTheme.dim)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

private struct MenuSettingOption {
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

private struct MenuSettingRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    let options: [MenuSettingOption]

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    option.action()
                } label: {
                    if option.isSelected {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(AppTheme.blue)
                Text(title)
                    .foregroundStyle(AppTheme.dim)
                    .font(AppTheme.font(.body, size: .medium))
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(AppTheme.text)
                    .font(AppTheme.font(.body, size: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppTheme.font(.caption, size: .medium))
                    .foregroundStyle(AppTheme.dim)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

private struct CopyableSettingRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(AppTheme.blue)
            Text(title)
                .foregroundStyle(AppTheme.dim)
                .font(AppTheme.font(.body, size: .medium))
            Spacer(minLength: 12)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(AppTheme.text)
                .font(AppTheme.font(.body, size: .medium))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = value
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        SettingsView(viewModel: SettingsViewModel(environment: .makeDefault()))
    }
}
