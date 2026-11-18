import CampusCore
import Foundation
import Testing

@Test func shippingCompositionShowsFourUnboundPlatformsWithoutAuthorization() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let core = try CampusCoreFactory.makeLocal(applicationSupportDirectory: directory)

    let snapshots = try await core.snapshot()
    #expect(snapshots.map(\.platform) == [.academic, .chaoxing, .campusSSO, .secondClassroom])
    #expect(snapshots.allSatisfy { $0.status == .unbound && !$0.canDisconnect })
    #expect(snapshots.filter(\.canConnect).map(\.platform) == [.academic])
    try await core.disconnect(.academic)
}
