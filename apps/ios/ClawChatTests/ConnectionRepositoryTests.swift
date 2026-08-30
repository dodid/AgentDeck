import XCTest
@testable import ClawChat

final class ConnectionRepositoryTests: XCTestCase {
    func testSecretsAreNotStoredInUserDefaults() async throws {
        let suiteName = "ConnectionRepositoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentialStore = MemoryCredentialStore()
        let repository = DefaultConnectionRepository(defaults: defaults, credentialStore: credentialStore)
        let config = ConnectionConfig(
            endpoint: "https://example.r2.cloudflarestorage.com",
            bucket: "relay",
            accessKeyID: "AKIA_TEST_SECRET",
            secretAccessKey: "super-secret-value",
            region: "auto",
            forcePathStyle: true
        )

        try await repository.saveConnectionConfig(config)

        let serializedDefaults = String(describing: defaults.dictionaryRepresentation())
        XCTAssertFalse(serializedDefaults.contains(config.accessKeyID))
        XCTAssertFalse(serializedDefaults.contains(config.secretAccessKey))
        let loaded = try await repository.loadConnectionConfig()
        XCTAssertEqual(loaded, config)
    }
}

private final class MemoryCredentialStore: ConnectionCredentialStore, @unchecked Sendable {
    private var credentials: ConnectionCredentials?

    func load() throws -> ConnectionCredentials? { credentials }
    func save(_ credentials: ConnectionCredentials) throws { self.credentials = credentials }
}
