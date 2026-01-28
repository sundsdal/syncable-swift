import Foundation

/// UserDefaults-based implementation of sync timestamp storage.
///
/// Persists sync timestamps and cursor IDs across app launches using UserDefaults.
/// Suitable for most apps where sync state should survive restarts.
public final class UserDefaultsSyncTimestampStorage: SyncTimestampStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let queue = DispatchQueue(label: "com.syncable.timestampstorage")

    /// Initialize with optional custom UserDefaults suite and key prefix
    /// - Parameters:
    ///   - defaults: The UserDefaults instance to use (defaults to .standard)
    ///   - keyPrefix: Prefix for stored keys (defaults to "syncable.")
    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "syncable."
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    private func prefixedKey(for key: String) -> String {
        "\(keyPrefix)\(key)"
    }

    public func getLastSyncTimestamp(for key: String) async -> Date? {
        queue.sync {
            defaults.object(forKey: prefixedKey(for: key)) as? Date
        }
    }

    public func setLastSyncTimestamp(_ timestamp: Date, for key: String) async {
        queue.sync {
            defaults.set(timestamp, forKey: prefixedKey(for: key))
        }
    }

    public func getCursorId(for key: String) async -> String? {
        queue.sync {
            defaults.string(forKey: prefixedKey(for: key))
        }
    }

    public func setCursorId(_ cursorId: String?, for key: String) async {
        queue.sync {
            if let cursorId {
                defaults.set(cursorId, forKey: prefixedKey(for: key))
            } else {
                defaults.removeObject(forKey: prefixedKey(for: key))
            }
        }
    }

    public func clearAll() async {
        queue.sync {
            let allKeys = defaults.dictionaryRepresentation().keys
            for key in allKeys where key.hasPrefix(keyPrefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
