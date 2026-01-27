import Foundation

/// UserDefaults-based implementation of sync timestamp storage.
///
/// Persists sync timestamps across app launches using UserDefaults.
/// Suitable for most apps where sync state should survive restarts.
public final class UserDefaultsSyncTimestampStorage: SyncTimestampStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let queue = DispatchQueue(label: "com.syncable.timestampstorage")

    /// Initialize with optional custom UserDefaults suite and key prefix
    /// - Parameters:
    ///   - defaults: The UserDefaults instance to use (defaults to .standard)
    ///   - keyPrefix: Prefix for stored keys (defaults to "syncable.lastSync.")
    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "syncable.lastSync."
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    private func key(for tableName: String) -> String {
        "\(keyPrefix)\(tableName)"
    }

    public func getLastSyncTimestamp(for tableName: String) async -> Date? {
        queue.sync {
            defaults.object(forKey: key(for: tableName)) as? Date
        }
    }

    public func setLastSyncTimestamp(_ timestamp: Date, for tableName: String) async {
        queue.sync {
            defaults.set(timestamp, forKey: key(for: tableName))
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
