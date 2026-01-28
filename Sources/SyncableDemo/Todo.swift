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

    // MARK: - GRDB Column Mapping

    enum Columns: String, ColumnExpression {
        case id, userId, updatedAt, deleted, syncedAt, title, isCompleted
    }
}

// MARK: - Database Schema

extension Todo {
    /// Create the todos table in the database
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            // Syncable required columns (TEXT for UUIDs to match Supabase)
            t.column(Columns.id.rawValue, .text).primaryKey()
            t.column(Columns.userId.rawValue, .text)
            t.column(Columns.updatedAt.rawValue, .datetime).notNull()
            t.column(Columns.deleted.rawValue, .boolean).notNull().defaults(to: false)
            t.column(Columns.syncedAt.rawValue, .datetime)

            // Custom columns
            t.column(Columns.title.rawValue, .text).notNull()
            t.column(Columns.isCompleted.rawValue, .boolean).notNull().defaults(to: false)
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
