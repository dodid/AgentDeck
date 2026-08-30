import Foundation

protocol DeviceRepository: Sendable {
    func loadDeviceProfile() async throws -> DeviceProfile
    func saveDeviceProfile(_ profile: DeviceProfile) async throws
}
