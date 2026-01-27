import Foundation

/// Type-erased wrapper for syncable models.
///
/// Used internally to work with heterogeneous collections of syncable types.
/// Captures the essential sync metadata without retaining the full model.
public struct AnySyncable: Sendable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let updatedAt: Date
    public let deleted: Bool
    public let needsSync: Bool
    public let syncRetryCount: Int
    public let tableName: String

    /// The underlying encodable data for upload
    private let _encode: @Sendable (JSONEncoder) throws -> Data

    public init<T: SyncableProtocol>(_ value: T) {
        self.id = value.id
        self.userId = value.userId
        self.updatedAt = value.updatedAt
        self.deleted = value.deleted
        self.needsSync = value.needsSync
        self.syncRetryCount = value.syncRetryCount
        self.tableName = T.tableName
        self._encode = { encoder in
            try encoder.encode(value)
        }
    }

    /// Encode the underlying value to JSON data
    public func encode(with encoder: JSONEncoder) throws -> Data {
        try _encode(encoder)
    }

    /// Check if this item has exceeded max retries
    public func hasExceededRetries(max: Int) -> Bool {
        syncRetryCount >= max
    }
}
