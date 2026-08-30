import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    var onCompleted: (() -> Void)?
    enum Step: Equatable {
        case welcome
        case howItWorks
        case createBucket
        case connect
    }

    let environment: AppEnvironment
    var step: Step = .welcome
    var draftConfig: ConnectionConfig = .empty
    var isWorking = false
    var errorMessage: String?
    var importErrorMessage: String?
    let fontSize: FontSizePreference = .medium

    init(environment: AppEnvironment, onCompleted: (() -> Void)? = nil) {
        self.environment = environment
        self.onCompleted = onCompleted

        Task {
            if let config = try? await environment.connectionRepository.loadConnectionConfig() {
                self.draftConfig = config
            }
        }
    }

    func advance() {
        switch step {
        case .welcome: step = .howItWorks
        case .howItWorks: step = .createBucket
        case .createBucket: step = .connect
        case .connect: break
        }
    }

    func goBack() {
        switch step {
        case .welcome: break
        case .howItWorks: step = .welcome
        case .createBucket: step = .howItWorks
        case .connect: step = .createBucket
        }
    }

    func updateConfig(_ config: ConnectionConfig) {
        draftConfig = config
    }

    var actualErrorMessage: String? {
        importErrorMessage ?? errorMessage
    }

    func verifyAndSave() async {
        isWorking = true
        defer { isWorking = false }
        do {
            errorMessage = nil
            importErrorMessage = nil
            try await environment.connectionRepository.verify(draftConfig)
            try await environment.connectionRepository.saveConnectionConfig(draftConfig)
            onCompleted?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
