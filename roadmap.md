# Syncable-Swift Implementation Roadmap (GRDB Edition)

## Phase 1: Core Protocols & Types ✅

### 1.1 Syncable Protocol
- [x] `SyncableProtocol` inheriting from `Codable`, `FetchableRecord`, `PersistableRecord`, `Identifiable`, `Sendable`
- [x] Required properties: `id` (UUID), `userId` (UUID?), `updatedAt` (Date), `deleted` (Bool)
- [x] `SyncableColumns` enum for type-safe column filtering
- [x] Default `databaseTableName` implementation

### 1.2 Timestamp Storage
- [x] `SyncTimestampStorage` protocol
- [x] `InMemorySyncTimestampStorage` implementation
- [x] `UserDefaultsSyncTimestampStorage` implementation

### 1.3 Registration
- [x] `SyncableRegistration` struct with type-erased operations
- [x] `SyncableRegistration.create<T>()` factory method

## Phase 2: SyncManager Core ✅

### 2.1 Initialization
- [x] `SyncManager` class definition
- [x] Accept `DatabaseWriter` (GRDB) in initializer
- [x] Accept `SupabaseClient`
- [x] Accept `SyncTimestampStorage`
- [x] Configurable `maxRows` batch size

### 2.2 State Management
- [x] Thread-safe state via NSLock (`userId`, `syncingEnabled`)
- [x] `setUserId(_:)` / `setSyncingEnabled(_:)` methods
- [x] `clearSyncState()` for logout

### 2.3 Registration
- [x] `register<T: SyncableProtocol>(_ type:)` method
- [x] `registeredTables` property

## Phase 3: Sync Operations ✅

### 3.1 Push (Local → Backend)
- [x] `push(registration:)` private implementation
- [x] Query logic: `updatedAt > lastPushedTimestamp`
- [x] Batch upsert to Supabase via `AnyJSON`
- [x] Update `lastPushedTimestamp` after success

### 3.2 Pull (Backend → Local)
- [x] `pull(registration:)` private implementation
- [x] Fetch from Supabase with `user_id` and `updated_at` filters
- [x] LWW conflict resolution in `upsertIfNewer`
- [x] Update `lastPulledTimestamp` after success

### 3.3 Public API
- [x] `sync()` - Full sync cycle for all registered types
- [x] `push<T>(_ type:)` - Push specific type
- [x] `pull<T>(_ type:)` - Pull specific type

## Phase 4: Testing ✅

### 4.1 Unit Tests
- [x] `SyncableProtocol` conformance tests
- [x] LWW conflict resolution tests
- [x] `SyncableRegistration` encode/decode tests
- [x] `SyncableRegistration` fetchUpdatedSince tests
- [x] `SyncableRegistration` upsertIfNewer tests

### 4.2 SyncManager Tests
- [x] Initialization tests
- [x] State management tests
- [x] Registration tests
- [x] Error type tests

### 4.3 Timestamp Storage Tests
- [x] `InMemorySyncTimestampStorage` tests
- [x] `UserDefaultsSyncTimestampStorage` tests

---

## Future Work

### Phase 5: Sync Loop
- [ ] Background `Task` loop with configurable interval
- [ ] Automatic sync on connectivity changes
- [ ] Error handling with exponential backoff

### Phase 6: Realtime Subscriptions
- [ ] Supabase Realtime integration
- [ ] `RealtimeSubscriptionManager` (skeleton exists)
- [ ] Conditional subscriptions based on multi-device activity

### Phase 7: Optimizations
- [ ] Echo prevention cache (avoid re-syncing own changes)
- [ ] `lastTimeOtherDeviceWasActive` logic
- [ ] GRDB `ValueObservation` for reactive UI updates

### Phase 8: Advanced Features
- [ ] Dead letter queue for failed items
- [ ] Retry logic with configurable max attempts
- [ ] Conflict resolution callbacks (custom merge strategies)

### Phase 9: Documentation & Examples
- [ ] Example app with SwiftUI + GRDB + Syncable
- [ ] "Getting Started" guide
- [ ] "Offline First Best Practices" guide

---

## Completed Items Summary

| Component | Status |
|-----------|--------|
| Package.swift (GRDB + Supabase) | ✅ |
| SyncableProtocol | ✅ |
| SyncableColumns | ✅ |
| SyncTimestampStorage | ✅ |
| InMemorySyncTimestampStorage | ✅ |
| UserDefaultsSyncTimestampStorage | ✅ |
| SyncableRegistration | ✅ |
| SyncManager | ✅ |
| Push sync (updatedAt > lastPushed) | ✅ |
| Pull sync with LWW | ✅ |
| Unit tests (35 passing) | ✅ |
| technical_design.md | ✅ |
| roadmap.md | ✅ |
