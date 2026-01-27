import Testing
import Foundation
@testable import Syncable

/// Test model conforming to SyncableProtocol
struct TestItem: SyncableProtocol {
    let id: UUID
    var userId: UUID
    var updatedAt: Date
    var deleted: Bool
    var needsSync: Bool
    var syncRetryCount: Int

    init(
        id: UUID = UUID(),
        userId: UUID = UUID(),
        updatedAt: Date = Date(),
        deleted: Bool = false,
        needsSync: Bool = false,
        syncRetryCount: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.needsSync = needsSync
        self.syncRetryCount = syncRetryCount
    }
}

@Suite("SyncableProtocol Tests")
struct SyncableProtocolTests {

    @Test("Default table name is derived from type name")
    func defaultTableName() {
        #expect(TestItem.tableName == "testitems")
    }

    @Test("Default max retries is 3")
    func defaultMaxRetries() {
        #expect(TestItem.maxSyncRetries == 3)
    }

    @Test("AnySyncable wraps model correctly")
    func anySyncableWrapping() throws {
        let item = TestItem(
            id: UUID(),
            userId: UUID(),
            updatedAt: Date(),
            deleted: false,
            needsSync: true,
            syncRetryCount: 2
        )

        let wrapped = AnySyncable(item)

        #expect(wrapped.id == item.id)
        #expect(wrapped.userId == item.userId)
        #expect(wrapped.deleted == item.deleted)
        #expect(wrapped.needsSync == item.needsSync)
        #expect(wrapped.syncRetryCount == 2)
        #expect(wrapped.tableName == "testitems")
    }

    @Test("AnySyncable encodes to JSON")
    func anySyncableEncoding() throws {
        let item = TestItem()
        let wrapped = AnySyncable(item)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try wrapped.encode(with: encoder)
        #expect(!data.isEmpty)

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data)
        #expect(json is [String: Any])
    }

    @Test("hasExceededRetries returns correct value")
    func retryExceeded() {
        var item = TestItem(syncRetryCount: 2)
        var wrapped = AnySyncable(item)

        #expect(!wrapped.hasExceededRetries(max: 3))

        item.syncRetryCount = 3
        wrapped = AnySyncable(item)
        #expect(wrapped.hasExceededRetries(max: 3))

        item.syncRetryCount = 5
        wrapped = AnySyncable(item)
        #expect(wrapped.hasExceededRetries(max: 3))
    }
}

@Suite("SyncQueueItem Tests")
struct SyncQueueItemTests {

    @Test("Increment retry preserves other fields")
    func incrementRetry() {
        let item = SyncQueueItem(
            id: UUID(),
            tableName: "test",
            data: Data(),
            retryCount: 0
        )

        let incremented = item.incrementingRetry(error: "Network error")

        #expect(incremented.id == item.id)
        #expect(incremented.tableName == item.tableName)
        #expect(incremented.retryCount == 1)
        #expect(incremented.lastError == "Network error")
    }

    @Test("Multiple retries accumulate")
    func multipleRetries() {
        var item = SyncQueueItem(
            id: UUID(),
            tableName: "test",
            data: Data()
        )

        item = item.incrementingRetry(error: "Error 1")
        item = item.incrementingRetry(error: "Error 2")
        item = item.incrementingRetry(error: "Error 3")

        #expect(item.retryCount == 3)
        #expect(item.lastError == "Error 3")
    }
}
