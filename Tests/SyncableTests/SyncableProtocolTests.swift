import Testing
import Foundation
import GRDB
@testable import Syncable

/// Test model conforming to SyncableProtocol
/// No CodingKeys needed - library handles snake_case conversion for Supabase
struct TestItem: SyncableProtocol {
    var id: UUID
    var userId: UUID?
    var updatedAt: Date
    var deleted: Bool
    var syncedAt: Date?
    var title: String

    init(
        id: UUID = UUID(),
        userId: UUID? = UUID(),
        updatedAt: Date = Date(),
        deleted: Bool = false,
        syncedAt: Date? = nil,
        title: String = "Test"
    ) {
        self.id = id
        self.userId = userId
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.syncedAt = syncedAt
        self.title = title
    }
}

/// Create an in-memory database with the TestItem table (camelCase columns)
func makeTestDatabase() throws -> DatabaseQueue {
    let dbQueue = try DatabaseQueue()
    try dbQueue.write { db in
        try db.create(table: "testitems") { t in
            t.column("id", .text).primaryKey()
            t.column("userId", .text)
            t.column("updatedAt", .datetime).notNull()
            t.column("deleted", .boolean).notNull().defaults(to: false)
            t.column("syncedAt", .datetime)
            t.column("title", .text).notNull()
        }
    }
    return dbQueue
}

@Suite("SyncableProtocol Tests")
struct SyncableProtocolTests {

    @Test("Default table name is derived from type name")
    func defaultTableName() {
        #expect(TestItem.databaseTableName == "testitems")
    }

    @Test("Model conforms to FetchableRecord and PersistableRecord")
    func grdbConformance() throws {
        let dbQueue = try makeTestDatabase()
        let item = TestItem()

        // Insert
        try dbQueue.write { db in
            try item.insert(db)
        }

        // Fetch
        let fetched = try dbQueue.read { db in
            try TestItem.fetchOne(db, key: item.id)
        }

        #expect(fetched != nil)
        #expect(fetched?.id == item.id)
        #expect(fetched?.title == item.title)
    }

    @Test("Model encodes to JSON correctly")
    func jsonEncoding() throws {
        let item = TestItem(
            id: UUID(),
            userId: UUID(),
            updatedAt: Date(),
            deleted: false,
            title: "Test Title"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(item)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil)
        #expect(json?["title"] as? String == "Test Title")
        #expect(json?["deleted"] as? Bool == false)
    }

    @Test("SyncableColumns can filter queries")
    func columnFiltering() throws {
        let dbQueue = try makeTestDatabase()
        let userId = UUID()

        let item1 = TestItem(userId: userId, title: "Item 1")
        let item2 = TestItem(userId: UUID(), title: "Item 2")
        let item3 = TestItem(userId: userId, deleted: true, title: "Deleted")

        try dbQueue.write { db in
            try item1.insert(db)
            try item2.insert(db)
            try item3.insert(db)
        }

        // Filter by userId
        let userItems = try dbQueue.read { db in
            try TestItem.filter(SyncableColumns.userId == userId).fetchAll(db)
        }
        #expect(userItems.count == 2)

        // Filter by deleted
        let activeItems = try dbQueue.read { db in
            try TestItem.filter(SyncableColumns.deleted == false).fetchAll(db)
        }
        #expect(activeItems.count == 2)
    }
}

@Suite("LWW Conflict Resolution Tests")
struct LWWConflictTests {

    @Test("Newer update wins over older")
    func newerWins() throws {
        let dbQueue = try makeTestDatabase()
        let id = UUID()
        let oldDate = Date().addingTimeInterval(-100)
        let newDate = Date()

        // Insert older record
        let oldItem = TestItem(id: id, updatedAt: oldDate, title: "Old")
        try dbQueue.write { db in
            try oldItem.insert(db)
        }

        // Try to update with newer record
        let newItem = TestItem(id: id, updatedAt: newDate, title: "New")
        try dbQueue.write { db in
            if let existing = try TestItem.fetchOne(db, key: id) {
                if newItem.updatedAt > existing.updatedAt {
                    try newItem.update(db)
                }
            }
        }

        let result = try dbQueue.read { db in
            try TestItem.fetchOne(db, key: id)
        }
        #expect(result?.title == "New")
    }

    @Test("Older update is ignored")
    func olderIgnored() throws {
        let dbQueue = try makeTestDatabase()
        let id = UUID()
        let oldDate = Date().addingTimeInterval(-100)
        let newDate = Date()

        // Insert newer record first
        let newItem = TestItem(id: id, updatedAt: newDate, title: "New")
        try dbQueue.write { db in
            try newItem.insert(db)
        }

        // Try to update with older record (should be ignored)
        let oldItem = TestItem(id: id, updatedAt: oldDate, title: "Old")
        try dbQueue.write { db in
            if let existing = try TestItem.fetchOne(db, key: id) {
                if oldItem.updatedAt > existing.updatedAt {
                    try oldItem.update(db)
                }
            }
        }

        let result = try dbQueue.read { db in
            try TestItem.fetchOne(db, key: id)
        }
        #expect(result?.title == "New")
    }
}

@Suite("SyncableRegistration Tests")
struct SyncableRegistrationTests {

    @Test("Registration captures table name")
    func registrationTableName() {
        let registration = SyncableRegistration.create(TestItem.self)
        #expect(registration.tableName == "testitems")
    }

    @Test("Registration can encode items")
    func registrationEncode() throws {
        let registration = SyncableRegistration.create(TestItem.self)
        let item = TestItem(title: "Encode Test")

        let data = try registration.encode(item)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["title"] as? String == "Encode Test")
    }

    @Test("Registration can decode items")
    func registrationDecode() throws {
        let registration = SyncableRegistration.create(TestItem.self)
        let originalItem = TestItem(title: "Decode Test")

        // Encode then decode
        let data = try registration.encode(originalItem)
        let decoded = try registration.decode(data) as? TestItem

        #expect(decoded?.id == originalItem.id)
        #expect(decoded?.title == "Decode Test")
    }

    @Test("Registration fetchDirty finds unsynced items")
    func fetchDirtyFindsUnsynced() throws {
        let dbQueue = try makeTestDatabase()
        let registration = SyncableRegistration.create(TestItem.self)
        let userId = UUID()

        // Item with no syncedAt (dirty)
        let unsyncedItem = TestItem(userId: userId, updatedAt: Date(), syncedAt: nil, title: "Unsynced")
        // Item with syncedAt = updatedAt (clean)
        let syncedItem = TestItem(userId: userId, updatedAt: Date(), syncedAt: Date(), title: "Synced")

        try dbQueue.write { db in
            try unsyncedItem.insert(db)
            try syncedItem.insert(db)
        }

        let dirty = try dbQueue.read { db in
            try registration.fetchDirty(db, userId, 100)
        }

        #expect(dirty.count == 1)
        #expect((dirty.first as? TestItem)?.title == "Unsynced")
    }

    @Test("Registration fetchDirty finds modified items")
    func fetchDirtyFindsModified() throws {
        let dbQueue = try makeTestDatabase()
        let registration = SyncableRegistration.create(TestItem.self)
        let userId = UUID()

        let syncTime = Date()
        // Item modified after sync (dirty)
        let modifiedItem = TestItem(userId: userId, updatedAt: syncTime.addingTimeInterval(100), syncedAt: syncTime, title: "Modified")
        // Item not modified since sync (clean)
        let cleanItem = TestItem(userId: userId, updatedAt: syncTime, syncedAt: syncTime, title: "Clean")

        try dbQueue.write { db in
            try modifiedItem.insert(db)
            try cleanItem.insert(db)
        }

        let dirty = try dbQueue.read { db in
            try registration.fetchDirty(db, userId, 100)
        }

        #expect(dirty.count == 1)
        #expect((dirty.first as? TestItem)?.title == "Modified")
    }

    @Test("Registration markAsSynced updates syncedAt")
    func markAsSyncedWorks() throws {
        let dbQueue = try makeTestDatabase()
        let registration = SyncableRegistration.create(TestItem.self)

        let item = TestItem(updatedAt: Date(), syncedAt: nil, title: "Test")
        try dbQueue.write { db in
            try item.insert(db)
        }

        // Verify item is dirty before
        let dirtyBefore = try dbQueue.read { db in
            try registration.fetchDirty(db, nil, 100)
        }
        #expect(dirtyBefore.count == 1)

        // Mark as synced
        try dbQueue.write { db in
            try registration.markAsSynced([item.id], db)
        }

        // Verify item is no longer dirty
        let dirtyAfter = try dbQueue.read { db in
            try registration.fetchDirty(db, nil, 100)
        }
        #expect(dirtyAfter.count == 0)

        // Verify syncedAt was set
        let fetched = try dbQueue.read { db in
            try TestItem.fetchOne(db, key: item.id)
        }
        #expect(fetched?.syncedAt == fetched?.updatedAt)
    }

    @Test("Registration upsertIfNewer applies LWW")
    func upsertIfNewer() throws {
        let dbQueue = try makeTestDatabase()
        let registration = SyncableRegistration.create(TestItem.self)
        let id = UUID()

        // Insert initial record
        let initial = TestItem(id: id, updatedAt: Date(), title: "Initial")
        try dbQueue.write { db in
            try initial.insert(db)
        }

        // Upsert newer record
        let newer = TestItem(id: id, updatedAt: Date().addingTimeInterval(100), title: "Newer")
        try dbQueue.write { db in
            try registration.upsertIfNewer(newer, db)
        }

        let result = try dbQueue.read { db in
            try TestItem.fetchOne(db, key: id)
        }
        #expect(result?.title == "Newer")

        // Upsert older record (should be ignored)
        let older = TestItem(id: id, updatedAt: Date().addingTimeInterval(-100), title: "Older")
        try dbQueue.write { db in
            try registration.upsertIfNewer(older, db)
        }

        let finalResult = try dbQueue.read { db in
            try TestItem.fetchOne(db, key: id)
        }
        #expect(finalResult?.title == "Newer") // Still "Newer", not "Older"
    }

    @Test("Registration encode excludes synced_at")
    func encodeExcludesSyncedAt() throws {
        let registration = SyncableRegistration.create(TestItem.self)
        let item = TestItem(syncedAt: Date(), title: "Test")

        let data = try registration.encode(item)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["title"] as? String == "Test")
        #expect(json?["synced_at"] == nil) // Should be excluded (snake_case)
    }

    @Test("Registration assignUserIdToOrphans assigns userId to null records")
    func assignUserIdToOrphans() throws {
        let dbQueue = try makeTestDatabase()
        let registration = SyncableRegistration.create(TestItem.self)
        let newUserId = UUID()

        // Create orphaned items (userId = nil)
        let orphan1 = TestItem(userId: nil, title: "Orphan 1")
        let orphan2 = TestItem(userId: nil, title: "Orphan 2")
        // Create owned item (should not be modified)
        let existingUserId = UUID()
        let owned = TestItem(userId: existingUserId, title: "Owned")

        try dbQueue.write { db in
            try orphan1.insert(db)
            try orphan2.insert(db)
            try owned.insert(db)
        }

        // Assign userId to orphans
        let count = try dbQueue.write { db in
            try registration.assignUserIdToOrphans(newUserId, db)
        }

        #expect(count == 2)

        // Verify orphans now have userId
        let items = try dbQueue.read { db in
            try TestItem.fetchAll(db)
        }

        let claimedOrphan1 = items.first { $0.id == orphan1.id }
        let claimedOrphan2 = items.first { $0.id == orphan2.id }
        let unchanged = items.first { $0.id == owned.id }

        #expect(claimedOrphan1?.userId == newUserId)
        #expect(claimedOrphan2?.userId == newUserId)
        #expect(unchanged?.userId == existingUserId) // Should not be modified
    }

    @Test("Registration assignUserIdToOrphans marks records as dirty")
    func assignUserIdToOrphansMarksDirty() throws {
        let dbQueue = try makeTestDatabase()
        let registration = SyncableRegistration.create(TestItem.self)

        // Create orphan that was previously "synced"
        let syncTime = Date().addingTimeInterval(-100)
        let orphan = TestItem(userId: nil, updatedAt: syncTime, syncedAt: syncTime, title: "Orphan")

        try dbQueue.write { db in
            try orphan.insert(db)
        }

        // Assign userId
        let newUserId = UUID()
        _ = try dbQueue.write { db in
            try registration.assignUserIdToOrphans(newUserId, db)
        }

        // Verify record is now dirty (syncedAt = nil, updatedAt updated)
        let updated = try dbQueue.read { db in
            try TestItem.fetchOne(db, key: orphan.id)
        }

        #expect(updated?.syncedAt == nil)
        #expect(updated?.updatedAt ?? Date.distantPast > syncTime)
        #expect(updated?.userId == newUserId)
    }
}
