# CampusCore

CampusCore is a local Swift 6 library for iOS 18 and macOS 15. Run its Swift Testing suite with `swift test --package-path ios/CampusCore` from the repository root.

`CampusCoreFactory.makeLocal()` composes an actor-backed `SessionCoordinator`, `KeychainCredentialVault`, `FileConnectionRegistry`, and `FileCampusCache`. Keep one coordinator per storage composition. The factory registers zero providers, so the shipping UI can display all four platforms without asking for credentials. Use `snapshot()` to read UI status and action availability, and `disconnect(_:)` to remove a binding or retry local cleanup. A registry read failure disables actions for the affected platform while leaving other rows visible.

## Credentials and cache

A provider defines its own authorization input. Its operations must isolate temporary cookies, requests, and web state, including cleanup on completion or cancellation. They return sensitive material to the coordinator, which uses memory by default. Keychain persistence requires an explicit choice and uses a nonsynchronizing, device-only item accessible while the device is unlocked. Keychain separates entries by platform and opaque binding ID. The registry stores that opaque ID with connection status and persistence policy. Cache files also use the platform and opaque binding ID. Each binding gets a randomized keyed digest of the remote user ID, so ordinary paths and registry records do not expose the ID or provide a stable lookup for guessed IDs. The cache is for normalized data and freshness timestamps. On iOS its files use complete file protection, and the cache is excluded from backup.

`probe(_:)` checks the current session. `refresh(_:)` reuses a valid session and tries recovery once after explicit expiration. Network failure preserves offline cached data. Same-platform checks share pending work. A provider result with a different remote identity cannot replace a binding’s credential. After a memory-only session is lost on restart, the binding reports that user action is required. This foundation uses disconnect followed by a new connection for interactive reauthorization, so the prior binding’s cache is deleted.

## Disconnect order

1. Invalidate and cancel the platform’s pending operation and drop its in-memory session. Late results cannot commit, including after a new binding is created.
2. Write a cleanup marker containing the old binding’s opaque namespace. If writing the marker fails, still attempt local deletion.
3. Remove the opted-in Keychain item, then delete the binding’s cache. Remove the registry entry last.
4. Retry `disconnect(_:)` if a deletion fails. Missing items count as success. A written cleanup marker survives restart and prevents session recovery or rebinding until cleanup completes. If storage rejects both the marker and deletion, the current instance keeps cleanup pending and returns the deletion error.
