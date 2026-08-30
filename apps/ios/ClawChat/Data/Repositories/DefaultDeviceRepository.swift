import Foundation

struct DefaultDeviceRepository: DeviceRepository, Sendable {
    private let defaults: UserDefaults
    private let key = "ClawChat.deviceProfile"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadDeviceProfile() async throws -> DeviceProfile {
        if let data = defaults.data(forKey: key) {
            return try decoder.decode(DeviceProfile.self, from: data)
        }
        let generated = makeDefaultProfile()
        let data = try encoder.encode(generated)
        defaults.set(data, forKey: key)
        return generated
    }

    func saveDeviceProfile(_ profile: DeviceProfile) async throws {
        let data = try encoder.encode(profile)
        defaults.set(data, forKey: key)
    }

    private func makeDefaultProfile() -> DeviceProfile {
        let adjectives = ["quiet", "warm", "blue", "misty", "silver", "gentle", "ember", "moss"]
        let nouns = ["otter", "sparrow", "pine", "river", "harbor", "comet", "fern", "lark"]
        let suffixChars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        let adjective = adjectives.randomElement() ?? "quiet"
        let noun = nouns.randomElement() ?? "otter"
        let suffix = String((0..<2).map { _ in suffixChars.randomElement() ?? "a" })
        let value = "\(adjective)-\(noun)-\(suffix)"
        return DeviceProfile(clientID: value, displayName: value, createdAt: Date())
    }
}
