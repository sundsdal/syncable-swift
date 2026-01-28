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

    /// Fetch dirty records that need to be pushed (syncedAt is nil OR updatedAt > syncedAt)
    let fetchDirty: @Sendable (Database, UUID?, Int) throws -> [any SyncableProtocol]

    /// Mark specific record IDs as synced (set syncedAt = pushedUpdatedAt)
    /// Only updates records where updatedAt matches pushedUpdatedAt to prevent race conditions
    let markAsSynced: @Sendable ([(id: UUID, pushedUpdatedAt: Date)], Database) throws -> Void

    /// Upsert a record into the database (LWW: only if newer)
    let upsertIfNewer: @Sendable (any SyncableProtocol, Database) throws -> Void

    /// Encode a record to JSON data for Supabase upload (excludes syncedAt)
    let encode: @Sendable (any SyncableProtocol) throws -> Data

    /// Assign userId to orphaned records (where userId is nil) and mark them dirty for sync
    /// Returns the count of records updated
    let assignUserIdToOrphans: @Sendable (UUID, Database) throws -> Int

    /// Create a registration for a specific Syncable type
    public static func create<T: SyncableProtocol>(_ type: T.Type) -> SyncableRegistration {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase  // Supabase snake_case → Swift camelCase

        return SyncableRegistration(
            tableName: T.databaseTableName,
            decode: { data in
                try decoder.decode(T.self, from: data)
            },
            fetchAll: { db, userId in
                // Exclude deleted items by default (tombstones should not appear in UI)
                var query = T.filter(SyncableColumns.deleted == false)
                if let userId {
                    query = query.filter(SyncableColumns.userId == userId)
                }
                return try query.fetchAll(db)
            },
            fetchDirty: { db, userId, limit in
                // Dirty = syncedAt is NULL OR updatedAt > syncedAt
                // Order by updatedAt, id for deterministic batching when over limit
                var query = T.filter(
                    SyncableColumns.syncedAt == nil ||
                    SyncableColumns.updatedAt > SyncableColumns.syncedAt
                )
                if let userId {
                    query = query.filter(SyncableColumns.userId == userId)
                }
                return try query
                    .order(SyncableColumns.updatedAt.asc)
                    .order(SyncableColumns.id.asc)
                    .limit(limit)
                    .fetchAll(db)
            },
            markAsSynced: { items, db in
                guard !items.isEmpty else { return }
                // Update syncedAt = pushedUpdatedAt only if updatedAt matches (prevents race condition)
                // If a local edit happened after the push snapshot, updatedAt won't match and record stays dirty
                for (id, pushedUpdatedAt) in items {
                    if var record = try T.fetchOne(db, key: id) {
                        // Only mark as synced if the record hasn't been modified since we pushed it
                        if record.updatedAt == pushedUpdatedAt {
                            record.syncedAt = pushedUpdatedAt
                            try record.update(db)
                        }
                        // else: record was modified after push, leave it dirty so it syncs again
                    }
                }
            },
            upsertIfNewer: { record, db in
                guard let typedRecord = record as? T else {
                    throw SyncableRegistrationError.typeMismatch
                }

                // LWW: Check if existing record and only update if incoming is newer
                if let existing = try T.fetchOne(db, key: typedRecord.id) {
                    if typedRecord.updatedAt > existing.updatedAt {
                        // Item from server is newer - update and mark as synced
                        var updated = typedRecord
                        updated.syncedAt = typedRecord.updatedAt  // Mark as synced (came from server)
                        try updated.update(db)
                    }
                    // else: existing is newer, ignore incoming
                } else {
                    // New item from server - insert and mark as synced
                    var newRecord = typedRecord
                    newRecord.syncedAt = typedRecord.updatedAt  // Mark as synced (came from server)
                    try newRecord.insert(db)
                }
            },
            encode: { record in
                guard let typedRecord = record as? T else {
                    throw SyncableRegistrationError.typeMismatch
                }
                // Encode to dictionary, remove syncedAt (local-only), then re-encode
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.keyEncodingStrategy = .convertToSnakeCase  // Swift camelCase → Supabase snake_case
                let data = try encoder.encode(typedRecord)
                guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw SyncableRegistrationError.encodingFailed
                }
                // Remove local-only field before sending to backend (snake_case after conversion)
                dict.removeValue(forKey: "synced_at")
                return try JSONSerialization.data(withJSONObject: dict)
            },
            assignUserIdToOrphans: { userId, db in
                // Find all records where userId is nil (created while anonymous)
                let orphans = try T.filter(SyncableColumns.userId == nil).fetchAll(db)
                var count = 0
                let now = Date()
                for var orphan in orphans {
                    orphan.userId = userId
                    orphan.updatedAt = now  // Mark as modified so it syncs
                    orphan.syncedAt = nil   // Ensure it's dirty
                    try orphan.update(db)
                    count += 1
                }
                return count
            }
        )
    }
}

/// Errors that can occur during registration operations
public enum SyncableRegistrationError: Error, LocalizedError {
    case typeMismatch
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .typeMismatch:
            return "Type mismatch in SyncableRegistration"
        case .encodingFailed:
            return "Failed to encode record for sync"
        }
    }
}
