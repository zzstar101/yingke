import CampusCore
import Foundation
import Observation

@MainActor
@Observable
final class AccountsModel {
    private var coordinator: (any SessionCoordinator)?
    private var snapshots: [CampusPlatform: ConnectionSnapshot] = [:]
    private var loadGeneration = 0
    private(set) var loadFailed = false

    func snapshot(for platform: CampusPlatform) -> ConnectionSnapshot? {
        snapshots[platform]
    }

    func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        do {
            let coordinator = try localCoordinator()
            let latest = try await coordinator.snapshot()
            guard loadGeneration == generation else { return }
            snapshots = Dictionary(uniqueKeysWithValues: latest.map { ($0.platform, $0) })
            loadFailed = false
        } catch {
            guard loadGeneration == generation else { return }
            snapshots = [:]
            loadFailed = true
        }
    }

    func disconnect(_ platform: CampusPlatform) async -> Bool {
        do {
            let coordinator = try localCoordinator()
            try await coordinator.disconnect(platform)
            await reload()
            return true
        } catch {
            await reload()
            return false
        }
    }

    private func localCoordinator() throws -> any SessionCoordinator {
        if let coordinator { return coordinator }
        let coordinator: any SessionCoordinator
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-bound-accounts") {
            coordinator = UITestAccounts()
        } else {
            coordinator = try CampusCoreFactory.makeLocal()
        }
        #else
        coordinator = try CampusCoreFactory.makeLocal()
        #endif
        self.coordinator = coordinator
        return coordinator
    }
}
