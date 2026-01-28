import Foundation
import GRDB
import Syncable

/// A simple Todo model demonstrating SyncableProtocol conformance.
struct Todo: SyncableProtocol {
    // MARK: - Required Syncable Fields

    var id: UUID
    var userId: UUID?
    var updatedAt: Date
    var deleted: Bool
    var syncedAt: Date?

    // MARK: - Custom Fields

    var title: String
    var isCompleted: Bool

    // MARK: - Coding Keys (maps Swift camelCase to PostgreSQL snake_case)

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case updatedAt = "updated_at"
        case deleted
        case syncedAt = "synced_at"
        case title
        case isCompleted = "is_completed"
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        title: String,
        isCompleted: Bool = false,
        updatedAt: Date = Date(),
        deleted: Bool = false,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.syncedAt = syncedAt
    }

    // MARK: - Table Name

    static var databaseTableName: String { "todos" }

    // MARK: - GRDB Column Mapping (must match CodingKeys for consistency)

    enum Columns: String, ColumnExpression {
        case id
        case userId = "user_id"
        case updatedAt = "updated_at"
        case deleted
        case syncedAt = "synced_at"
        case title
        case isCompleted = "is_completed"
    }
}

// MARK: - Database Schema

extension Todo {
    /// Create the todos table in the database (local GRDB schema)
    /// Column names use snake_case to match Supabase/PostgreSQL convention
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            // Syncable required columns (TEXT for UUIDs to match Supabase)
            t.column("id", .text).primaryKey()
            t.column("user_id", .text)
            t.column("updated_at", .datetime).notNull()
            t.column("deleted", .boolean).notNull().defaults(to: false)
            t.column("synced_at", .datetime)  // Local-only, not in Supabase

            // Custom columns
            t.column("title", .text).notNull()
            t.column("is_completed", .boolean).notNull().defaults(to: false)
        }
    }
}

// MARK: - Convenience Methods

extension Todo {
    /// Mark this todo as completed and update timestamp
    mutating func complete() {
        isCompleted = true
        updatedAt = Date()
    }

    /// Mark this todo as deleted (soft delete) and update timestamp
    mutating func markDeleted() {
        deleted = true
        updatedAt = Date()
    }
}
