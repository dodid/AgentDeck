import Foundation

protocol ConnectionRepository: Sendable {
    func loadConnectionConfig() async throws -> ConnectionConfig?
    func saveConnectionConfig(_ config: ConnectionConfig) async throws
    func verify(_ config: ConnectionConfig) async throws
}
