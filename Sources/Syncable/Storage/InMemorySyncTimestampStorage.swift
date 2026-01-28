import Foundation

/// In-memory implementation of sync timestamp storage.
///
/// Useful for testing or when persistence isn't needed.
/// All state is lost when the app terminates.
public actor InMemorySyncTimestampStorage: SyncTimestampStorage {
    private var timestamps: [String: Date] = [:]
    private var cursorIds: [String: String] = [:]

    public init() {}

    public func getLastSyncTimestamp(for key: String) -> Date? {
        timestamps[key]
    }

    public func setLastSyncTimestamp(_ timestamp: Date, for key: String) {
        timestamps[key] = timestamp
    }

    public func getCursorId(for key: String) -> String? {
        cursorIds[key]
    }

    public func setCursorId(_ cursorId: String?, for key: String) {
        if let cursorId {
            cursorIds[key] = cursorId
        } else {
            cursorIds.removeValue(forKey: key)
        }
    }

    public func clearAll() {
        timestamps.removeAll()
        cursorIds.removeAll()
    }
}
