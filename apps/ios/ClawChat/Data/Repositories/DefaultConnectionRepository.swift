import Foundation

struct DefaultConnectionRepository: ConnectionRepository, Sendable {
    private let defaults: UserDefaults
    private let credentialStore: any ConnectionCredentialStore
    private let key = "ClawChat.connectionConfig.v3"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any ConnectionCredentialStore = KeychainConnectionCredentialStore()
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
    }

    func loadConnectionConfig() async throws -> ConnectionConfig? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let metadata = try decoder.decode(ConnectionMetadata.self, from: data)
        guard let credentials = try credentialStore.load() else { return nil }
        return normalize(ConnectionConfig(
            endpoint: metadata.endpoint,
            bucket: metadata.bucket,
            accessKeyID: credentials.accessKeyID,
            secretAccessKey: credentials.secretAccessKey,
            region: metadata.region,
            forcePathStyle: metadata.forcePathStyle
        ))
    }

    func saveConnectionConfig(_ config: ConnectionConfig) async throws {
        let normalized = normalize(config)
        try validate(normalized)
        try credentialStore.save(ConnectionCredentials(
            accessKeyID: normalized.accessKeyID,
            secretAccessKey: normalized.secretAccessKey
        ))
        let data = try encoder.encode(ConnectionMetadata(
            endpoint: normalized.endpoint,
            bucket: normalized.bucket,
            region: normalized.region,
            forcePathStyle: normalized.forcePathStyle
        ))
        defaults.set(data, forKey: key)
    }

    func verify(_ config: ConnectionConfig) async throws {
        let normalized = normalize(config)
        try validate(normalized)

        let service = RelayDiscoveryService(config: normalized)
        do {
            _ = try await service.discoverGateways()
        } catch RelayDiscoveryError.noGatewaysFound {
            // Credentials and bucket access are valid even if no OpenClaw instance
            // has published an identity document yet.
            return
        } catch {
            throw mapVerificationError(error)
        }
    }

    private func validate(_ config: ConnectionConfig) throws {
        guard config.isComplete else {
            throw ConnectionRepositoryError.incompleteConfiguration
        }
        guard URL(string: config.endpoint) != nil else {
            throw ConnectionRepositoryError.invalidEndpoint
        }
    }

    private func normalize(_ config: ConnectionConfig) -> ConnectionConfig {
        ConnectionConfig(
            endpoint: config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)),
            bucket: config.bucket.trimmingCharacters(in: .whitespacesAndNewlines),
            accessKeyID: config.accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: config.secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            region: config.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "auto" : config.region.trimmingCharacters(in: .whitespacesAndNewlines),
            forcePathStyle: true
        )
    }

    private func mapVerificationError(_ error: Error) -> Error {
        if let connectionError = error as? ConnectionRepositoryError {
            return connectionError
        }
        if let discoveryError = error as? RelayDiscoveryError {
            switch discoveryError {
            case .noGatewaysFound:
                return discoveryError
            case .unsupportedProtocol:
                return discoveryError
            case .discoveryUnavailable:
                return ConnectionRepositoryError.discoveryFailed(String(localized: "Could not access the relay bucket with those settings."))
            }
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.caseInsensitiveCompare("data missing") == .orderedSame {
            return ConnectionRepositoryError.discoveryFailed(String(localized: "Could not access the relay bucket with those settings."))
        }
        guard !message.isEmpty else {
            return ConnectionRepositoryError.discoveryFailed(String(localized: "Could not verify the relay connection."))
        }
        return ConnectionRepositoryError.discoveryFailed(message)
    }
}

private struct ConnectionMetadata: Codable {
    let endpoint: String
    let bucket: String
    let region: String
    let forcePathStyle: Bool
}

enum ConnectionRepositoryError: LocalizedError {
    case incompleteConfiguration
    case invalidEndpoint
    case discoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .incompleteConfiguration:
            return String(localized: "Connection details are incomplete.")
        case .invalidEndpoint:
            return String(localized: "The endpoint URL is invalid.")
        case .discoveryFailed(let message):
            return message
        }
    }
}
