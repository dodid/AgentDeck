import SwiftUI

private enum MainShellRoute: Hashable {
    case session(SessionID)
    case settings
    case connection
}

struct MainShellView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let environment: AppEnvironment
    @State private var path: [MainShellRoute] = []
    @State private var selectedSessionID: SessionID?
    @State private var chatListViewModel: ChatListViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        self._chatListViewModel = State(initialValue: ChatListViewModel(environment: environment))
    }

    var body: some View {
        Group {
            if usesSplitView {
                splitShell
            } else {
                compactShell
            }
        }
        .onAppear {
            synchronizeNavigationState(forSplitView: usesSplitView)
        }
        .onChange(of: usesSplitView) { _, isSplitView in
            synchronizeNavigationState(forSplitView: isSplitView)
        }
    }

    private var compactShell: some View {
        NavigationStack(path: $path) {
            ChatListView(
                viewModel: chatListViewModel,
                openSession: openSession
            )
                .toolbar { settingsToolbar }
                .navigationDestination(for: MainShellRoute.self, destination: destinationView)
        }
    }

    private var splitShell: some View {
        NavigationSplitView {
            ChatListView(
                viewModel: chatListViewModel,
                selectedSessionID: Binding(
                    get: { selectedSessionID },
                    set: { newValue in
                        selectedSessionID = newValue
                        path.removeAll()
                    }
                )
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } detail: {
            NavigationStack(path: $path) {
                detailRoot
                    .toolbar { settingsToolbar }
                    .navigationDestination(for: MainShellRoute.self, destination: destinationView)
            }
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        if let selectedSessionID {
            ChatDetailView(viewModel: ChatDetailViewModel(environment: environment, sessionID: selectedSessionID))
                .id(selectedSessionID)
        } else {
            SplitViewPlaceholder()
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                path.append(.settings)
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(String(localized: "Settings"))
        }
    }

    @ViewBuilder
    private func destinationView(for route: MainShellRoute) -> some View {
        switch route {
        case .session(let sessionID):
            ChatDetailView(viewModel: ChatDetailViewModel(environment: environment, sessionID: sessionID))
        case .settings:
            SettingsView(
                viewModel: SettingsViewModel(environment: environment),
                openConnectionEditor: {
                    path.append(.connection)
                }
            )
        case .connection:
            ConnectionEditorView(viewModel: ConnectionEditorViewModel(environment: environment))
        }
    }

    private var usesSplitView: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var activeSessionRoute: SessionID? {
        for route in path.reversed() {
            if case let .session(sessionID) = route {
                return sessionID
            }
        }
        return nil
    }

    private func openSession(_ sessionID: SessionID) {
        if let activeSessionRoute {
            if activeSessionRoute == sessionID {
                return
            }
            path.removeAll { route in
                if case .session = route {
                    return true
                }
                return false
            }
        }
        path.append(.session(sessionID))
    }

    private func synchronizeNavigationState(forSplitView isSplitView: Bool) {
        if isSplitView {
            if selectedSessionID == nil, let sessionID = activeSessionRoute {
                selectedSessionID = sessionID
            }
            path.removeAll { route in
                if case .session = route {
                    return true
                }
                return false
            }
            return
        }

        guard let selectedSessionID else { return }

        if activeSessionRoute == nil {
            let insertIndex = path.firstIndex { route in
                if case .session = route {
                    return true
                }
                return false
            } ?? 0
            path.insert(.session(selectedSessionID), at: insertIndex)
        }
    }
}

private struct SplitViewPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            String(localized: "Select a chat"),
            systemImage: "bubble.left.and.bubble.right",
            description: Text(String(localized: "Choose a conversation from the sidebar to view its transcript."))
        )
        .foregroundStyle(AppTheme.dim)
    }
}

#Preview {
    MainShellView(environment: .makeDefault())
}
