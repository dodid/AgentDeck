import SwiftUI
import UIKit

struct SessionInspectorView: View {
    @State var viewModel: SessionInspectorViewModel
    @State private var showingRenamePrompt = false
    @State private var renameDraft = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Server") {
                    InspectorCopyableRow(icon: "server.rack", title: "Name", value: nonEmpty(viewModel.gatewayDisplayName))
                    InspectorCopyableRow(icon: "network", title: "ID", value: nonEmpty(viewModel.gatewayID))
                }
                .listRowBackground(AppTheme.panel)

                Section("Session") {
                    InspectorCopyableRow(icon: "text.bubble", title: "Name", value: nonEmpty(viewModel.sessionTitle))
                    InspectorCopyableRow(icon: "tag", title: "Type", value: nonEmpty(viewModel.sessionKind))
                    InspectorCopyableRow(icon: "square.stack.3d.up", title: "Agent", value: nonEmpty(viewModel.agentID))
                    if !viewModel.sourceChannel.isEmpty {
                        InspectorCopyableRow(icon: "arrow.triangle.branch", title: "Source", value: viewModel.sourceChannel)
                    }
                    InspectorCopyableRow(icon: "number", title: "Conversation", value: nonEmpty(viewModel.conversationID))
                    InspectorCopyableRow(icon: "number.square", title: "Instance", value: nonEmpty(viewModel.instanceID))
                    InspectorCopyableRow(icon: "character.cursor.ibeam", title: "Thread", value: nonEmpty(viewModel.threadID))
                    RelativeTimeInfoRow(icon: "arrow.triangle.2.circlepath", title: "Message fetch", date: viewModel.lastMessageFetchAt)
                }
                .listRowBackground(AppTheme.panel)

                Section("Device") {
                    InspectorCopyableRow(icon: "number", title: "Device ID", value: nonEmpty(viewModel.deviceID))
                    if viewModel.deviceName != viewModel.deviceID {
                        InspectorCopyableRow(icon: "iphone", title: "Device", value: nonEmpty(viewModel.deviceName))
                    }
                }
                .listRowBackground(AppTheme.panel)

                Section("Actions") {
                    Button {
                        renameDraft = viewModel.localSessionTitle
                        showingRenamePrompt = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "pencil")
                                .frame(width: 18)
                                .foregroundStyle(AppTheme.blue)
                            Text("Rename session")
                                .foregroundStyle(AppTheme.text)
                                .font(AppTheme.font(.body, size: .medium))
                            Spacer(minLength: 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(AppTheme.panel)

            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Rename Session", isPresented: $showingRenamePrompt) {
                TextField("Leave blank to restore", text: $renameDraft)
                Button("Save") {
                    let value = renameDraft
                    Task {
                        await viewModel.renameSessionLocally(to: value)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Use a more friendly name to identify the session")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshSession() }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isRefreshing)
                    .accessibilityLabel(String(localized: "Refresh session"))
                }
            }
        }
    }

    private func nonEmpty(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }
}

private struct InspectorCopyableRow: View {
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

private struct RelativeTimeInfoRow: View {
    let icon: String
    let title: LocalizedStringKey
    let date: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(AppTheme.blue)
                Text(title)
                    .foregroundStyle(AppTheme.dim)
                    .font(AppTheme.font(.body, size: .medium))
                Spacer(minLength: 12)
                Text(relativeText)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(AppTheme.text)
                    .font(AppTheme.font(.body, size: .medium))
            }
            .padding(.vertical, 2)
        }
    }

    private var relativeText: String {
        guard let date else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }
}

#Preview {
    SessionInspectorView(viewModel: SessionInspectorViewModel(environment: .makeDefault(), sessionID: SessionID(rawValue: "preview")))
}
