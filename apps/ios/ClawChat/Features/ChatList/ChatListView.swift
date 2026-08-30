import SwiftUI

struct ChatListView: View {
    @State var viewModel: ChatListViewModel
    let selectedSessionID: Binding<SessionID?>?
    let openSession: ((SessionID) -> Void)?

    init(
        viewModel: ChatListViewModel,
        selectedSessionID: Binding<SessionID?>? = nil,
        openSession: ((SessionID) -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.selectedSessionID = selectedSessionID
        self.openSession = openSession
    }

    var body: some View {
        Group {
            if let selectedSessionID {
                List(selection: selectedSessionID) {
                    listContent
                }
            } else {
                List {
                    listContent
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.bg)
        .navigationTitle("ClawChat")
        .overlay {
            if viewModel.sections.isEmpty {
                NoChatsEmptyView(isLoading: viewModel.isRefreshing) {
                    Task { await viewModel.refresh() }
                }
            }
        }
        .task {
            await viewModel.refresh()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if let errorMessage = viewModel.errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.yellow)
            }
            .listRowBackground(AppTheme.panel)
        }

        if !viewModel.sections.isEmpty {
            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        sessionRow(for: row)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(rowBackground(for: row))
                    }
                } header: {
                    GatewaySectionHeaderView(title: section.title)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(for row: ChatListRowViewData) -> some View {
        if selectedSessionID != nil {
            sessionRowLabel(for: row)
                .contentShape(Rectangle())
                .tag(row.id)
        } else if let openSession {
            Button {
                openSession(row.id)
            } label: {
                sessionRowLabel(for: row)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ChatDetailView(viewModel: ChatDetailViewModel(environment: viewModel.environment, sessionID: row.id))
            } label: {
                sessionRowLabel(for: row)
            }
        }
    }

    private func rowBackground(for row: ChatListRowViewData) -> some View {
        return Rectangle()
            .fill(isSelected(row) ? AppTheme.blue.opacity(0.12) : AppTheme.panel)
    }

    private func sessionRowLabel(for row: ChatListRowViewData) -> some View {
        let isSelected = isSelected(row)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                SessionLabelView(
                    label: row.title,
                    secondaryColor: AppTheme.text
                )
                Spacer(minLength: 8)
                if row.requiresSubscription && !viewModel.environment.subscriptionController.hasUnlockedAgentAccess {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.yellow)
                }
                Text(row.timestampText)
                    .font(.caption)
                    .foregroundStyle(isSelected ? AppTheme.text.opacity(0.82) : AppTheme.dim)
            }

            HStack(spacing: 8) {
                Text(row.previewText)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? AppTheme.text.opacity(0.86) : AppTheme.dim)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if row.unreadCount > 0 {
                    Text("\(row.unreadCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue, in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isSelected(_ row: ChatListRowViewData) -> Bool {
        selectedSessionID?.wrappedValue == row.id
    }
}

private struct GatewaySectionHeaderView: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "server.rack")
                .font(AppTheme.font(.subheadline, size: .medium, weight: .semibold))
            Text(title)
                .font(AppTheme.font(.subheadline, size: .medium, weight: .semibold))
                .foregroundStyle(AppTheme.text)
            Spacer()
        }
        .padding(.top, 4)
        .textCase(nil)
    }
}

private struct NoChatsEmptyView: View {
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.dim)

            VStack(spacing: 8) {
                Text("No agent platform found")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.text)

                Text("Your relay bucket is connected, but no OpenClaw, Hermes, or other relay server has been discovered yet.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.blue)
                        .frame(width: 22)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Install a relay integration")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.text)
                        Text("Install the OpenClaw r2-relay channel or Hermes r2-relay adapter, then configure it with the same R2 bucket credentials. Once running, tap Refresh to discover it.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppTheme.dim)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.panel)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button(action: onRefresh) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppTheme.blue)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isLoading ? "Refreshing…" : "Refresh")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(AppTheme.blue.opacity(0.10))
                .clipShape(Capsule())
            }
            .disabled(isLoading)

            Spacer()
        }
        .padding(.horizontal, 32)
        .background(AppTheme.bg)
    }
}

#Preview {
    NavigationStack {
        ChatListView(viewModel: ChatListViewModel(environment: .makeDefault()))
    }
}
