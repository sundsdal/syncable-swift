import Foundation
import GRDB

/// Registration information for a Syncable type with the SyncManager.
///
/// This struct captures the type-erased operations needed to sync a specific model type.
/// Created internally when you register a Syncable type with the SyncManager.
public struct SyncableRegistration: Sendable {
    /// The database/Supabase table name for this type
    public let tableName: String

    /// Decode JSON data into a Syncable instance
    let decode: @Sendable (Data) throws -> any SyncableProtocol

    /// Fetch all records for a user from the database
    let fetchAll: @Sendable (Database, UUID?) throws -> [any SyncableProtocol]

    /// Fetch records updated after a given timestamp
    let fetchUpdatedSince: @Sendable (Database, Date?, UUID?) throws -> [any SyncableProtocol]

    /// Upsert a record into the database (LWW: only if newer)
    let upsertIfNewer: @Sendable (any SyncableProtocol, Database) throws -> Void

    /// Encode a record to JSON data for Supabase upload
    let encode: @Sendable (any SyncableProtocol) throws -> Data

    /// Create a registration for a specific Syncable type
    public static func create<T: SyncableProtocol>(_ type: T.Type) -> SyncableRegistration {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        return SyncableRegistration(
            tableName: T.databaseTableName,
            decode: { data in
                try decoder.decode(T.self, from: data)
            },
            fetchAll: { db, userId in
                if let userId {
                    return try T.filter(SyncableColumns.userId == userId).fetchAll(db)
                } else {
                    return try T.fetchAll(db)
                }
            },
            fetchUpdatedSince: { db, timestamp, userId in
                var query = T.all()
                if let userId {
                    query = query.filter(SyncableColumns.userId == userId)
                }
                if let timestamp {
                    query = query.filter(SyncableColumns.updatedAt > timestamp)
                }
                return try query.fetchAll(db)
            },
            upsertIfNewer: { record, db in
                guard let typedRecord = record as? T else {
                    throw SyncableRegistrationError.typeMismatch
                }

                // LWW: Check if existing record and only update if incoming is newer
                if let existing = try T.fetchOne(db, key: typedRecord.id) {
                    if typedRecord.updatedAt > existing.updatedAt {
                        try typedRecord.update(db)
                    }
                    // else: existing is newer, ignore incoming
                } else {
                    try typedRecord.insert(db)
                }
            },
            encode: { record in
                guard let typedRecord = record as? T else {
                    throw SyncableRegistrationError.typeMismatch
                }
                return try encoder.encode(typedRecord)
            }
        )
    }
}

/// Errors that can occur during registration operations
public enum SyncableRegistrationError: Error, LocalizedError {
    case typeMismatch

    public var errorDescription: String? {
        switch self {
        case .typeMismatch:
            return "Type mismatch in SyncableRegistration"
        }
    }
}
