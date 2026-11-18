import Foundation

public enum CampusCoreFactory {
    /// Creates the app's local coordinator. No campus adapters are registered in this release.
    public static func makeLocal(applicationSupportDirectory: URL? = nil) throws -> any SessionCoordinator {
        let applicationSupport = try applicationSupportDirectory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let root = applicationSupport.appending(path: "CampusCore", directoryHint: .isDirectory)
        let registry = try FileConnectionRegistry(directory: root.appending(path: "Connections", directoryHint: .isDirectory))
        let cache = try FileCampusCache(directory: root.appending(path: "Cache", directoryHint: .isDirectory))
        let vault = KeychainCredentialVault(service: (Bundle.main.bundleIdentifier ?? "ink.zzstar.yingke") + ".campus-core.v1")
        return LocalSessionCoordinator(providers: [:], registry: registry, vault: vault, cache: cache)
    }
}
