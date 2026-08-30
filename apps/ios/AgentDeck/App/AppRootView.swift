import SwiftUI
import Observation
import Combine

extension Notification.Name {
    static let clawChatThemeDidChange = Notification.Name("AgentDeckThemeDidChange")
    static let clawChatAppearanceDidChange = Notification.Name("AgentDeckAppearanceDidChange")
}

@MainActor
@Observable
final class ThemeController {
    private let settingsRepository: SettingsRepository
    var appearancePreference: AppThemePreference = .system

    init(settingsRepository: SettingsRepository) {
        self.settingsRepository = settingsRepository
    }

    func load() async {
        if let settings = try? await settingsRepository.loadAppearanceSettings() {
            appearancePreference = settings.theme
        }
    }

    func apply(_ preference: AppThemePreference) {
        appearancePreference = preference
    }

    var colorScheme: ColorScheme? {
        switch appearancePreference {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let environment: AppEnvironment
    @State private var coordinator: AppCoordinatorViewModel
    @State private var themeController: ThemeController

    init() {
        let environment = AppEnvironment.makeDefault()
        self.environment = environment
        self._coordinator = State(initialValue: AppCoordinatorViewModel(environment: environment))
        self._themeController = State(initialValue: ThemeController(settingsRepository: environment.settingsRepository))
    }

    var body: some View {
        Group {
            switch coordinator.rootRoute {
            case .onboarding:
                OnboardingView(viewModel: OnboardingViewModel(environment: environment, onCompleted: {
                    coordinator.completeOnboarding()
                }))
            case .main:
                MainShellView(environment: environment)
            }
        }
        .preferredColorScheme(themeController.colorScheme)
        .task {
            await coordinator.bootstrap()
            await environment.chatAppearanceController.load()
            await environment.subscriptionController.start()
            await themeController.load()
            await handleScenePhase(scenePhase)
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                await handleScenePhase(newPhase)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clawChatThemeDidChange)) { notification in
            guard let rawValue = notification.object as? String,
                  let preference = AppThemePreference(rawValue: rawValue) else { return }
            themeController.apply(preference)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            await environment.syncRepository.startPolling()
            await environment.syncRepository.requestImmediateSync(reason: .foreground)
            try? await environment.discoveryRepository.refreshGateways(force: false)
            await environment.chatAppearanceController.load()
            await environment.subscriptionController.refreshEntitlements()
            await themeController.load()
        case .inactive:
            break
        case .background:
            await environment.syncRepository.stopPolling()
        @unknown default:
            break
        }
    }
}

#Preview {
    AppRootView()
}
