#if DEBUG
import CampusCore

/// Supplies synthetic account state for the UI flow. Core tests exercise persistent cleanup separately.
actor UITestAccounts: SessionCoordinator {
    private var boundPlatforms: Set<CampusPlatform> = [.academic, .chaoxing]

    func snapshot() -> [ConnectionSnapshot] {
        CampusPlatform.allCases.map { platform in
            let isBound = boundPlatforms.contains(platform)
            return ConnectionSnapshot(
                platform: platform,
                status: isBound ? .connected : .unbound,
                canConnect: false,
                canDisconnect: isBound
            )
        }
    }

    func disconnect(_ platform: CampusPlatform) {
        boundPlatforms.remove(platform)
    }

    func connect(_ platform: CampusPlatform, using authorization: any ProviderAuthorization, persistence: CredentialPersistence) throws {
        throw SessionFailure.unsupported
    }

    func probe(_ platform: CampusPlatform) throws -> ConnectionStatus {
        throw SessionFailure.unsupported
    }

    func refresh(_ platform: CampusPlatform) throws -> ConnectionStatus {
        throw SessionFailure.unsupported
    }
}
#endif
