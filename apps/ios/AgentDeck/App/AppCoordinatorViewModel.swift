import Foundation
import Observation

@MainActor
@Observable
final class AppCoordinatorViewModel {
    enum RootRoute: Equatable {
        case onboarding
        case main
    }

    private let environment: AppEnvironment
    var rootRoute: RootRoute = .onboarding

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func bootstrap() async {
        do {
            if let config = try await environment.connectionRepository.loadConnectionConfig(), config.isComplete {
                rootRoute = .main
            } else {
                rootRoute = .onboarding
            }
        } catch {
            rootRoute = .onboarding
        }
    }

    func completeOnboarding() {
        rootRoute = .main
    }
}
