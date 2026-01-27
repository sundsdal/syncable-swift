import Foundation
import SwiftData

/// Configuration for a registered syncable type.
///
/// Stores metadata and operations needed to sync a specific model type.
public struct SyncableRegistration<T: SyncableProtocol>: Sendable {
    /// The table name in Supabase
    public let tableName: String

    /// Maximum retries before dead letter queue
    public let maxRetries: Int

    /// Decode JSON data into the model type
    public let decode: @Sendable (Data) throws -> T

    public init(
        tableName: String = T.tableName,
        maxRetries: Int = T.maxSyncRetries,
        decode: @escaping @Sendable (Data) throws -> T
    ) {
        self.tableName = tableName
        self.maxRetries = maxRetries
        self.decode = decode
    }
}

/// Type-erased registration for storing in collections
public struct AnySyncableRegistration: Sendable {
    public let tableName: String
    public let maxRetries: Int

    /// Decode and wrap in AnySyncable
    public let decodeToAny: @Sendable (Data) throws -> AnySyncable

    public init<T: SyncableProtocol>(_ registration: SyncableRegistration<T>) {
        self.tableName = registration.tableName
        self.maxRetries = registration.maxRetries
        self.decodeToAny = { data in
            let value = try registration.decode(data)
            return AnySyncable(value)
        }
    }
}
