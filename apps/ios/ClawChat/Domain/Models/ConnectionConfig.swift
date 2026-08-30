import Foundation

struct ConnectionConfig: Equatable, Codable, Sendable {
    var endpoint: String
    var bucket: String
    var accessKeyID: String
    var secretAccessKey: String
    var region: String
    var forcePathStyle: Bool

    static let empty = ConnectionConfig(
        endpoint: "",
        bucket: "",
        accessKeyID: "",
        secretAccessKey: "",
        region: "auto",
        forcePathStyle: true
    )

    var isComplete: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
