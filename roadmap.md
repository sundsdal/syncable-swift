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

## Phase 5: Background Sync Loop ✅

### 5.1 Exponential Backoff
- [x] `ExponentialBackoff` struct with configurable initial/max delay
- [x] `recordFailure()` returns delay and doubles internal state
- [x] `reset()` returns to initial delay after success

### 5.2 Network Monitoring
- [x] `NetworkMonitor` using Network.framework
- [x] Thread-safe `isConnected` property
- [x] Callback when connectivity restored

### 5.3 Sync Loop Integration
- [x] `syncInterval` configurable property (default 30s)
- [x] `startSyncLoop(interval:)` method
- [x] `stopSyncLoop()` method
- [x] Automatic sync on network restore
- [x] Exponential backoff on failures (1s → 2s → 4s → ... → 60s max)
- [x] `clearSyncState()` stops sync loop

### 5.4 Testing
- [x] `ExponentialBackoff` unit tests
- [x] `NetworkMonitor` unit tests
- [x] Sync loop lifecycle tests

---

## Phase 6: Realtime Subscriptions ✅

- [x] Supabase Realtime integration
- [x] `RealtimeSubscriptionManager` with actor-based concurrency
- [x] `startRealtime()` / `stopRealtime()` methods on SyncManager
- [x] `onRealtimeChange` callback for UI refresh

## Phase 7: Echo Prevention ✅

- [x] `EchoPreventionCache` to avoid re-syncing own changes
- [x] TTL-based expiration for cache entries (60s default)
- [x] Integration with push/pull cycle

## Phase 8: Documentation & Examples ✅

- [x] Comprehensive README with:
  - [x] Installation instructions (SPM)
  - [x] Quick Start section with demo link
  - [x] Step-by-step usage guide
  - [x] Column naming convention documentation
  - [x] `syncedAt` explanation
  - [x] Anonymous to authenticated flow
  - [x] Error handling guidance
  - [x] API reference tables
- [x] CLI Demo app (`SyncableDemo`) with:
  - [x] Complete `Todo` model example
  - [x] Interactive commands (add, list, complete, delete, sync, online/offline)
  - [x] Supabase migration file
- [x] Technical design document (`technical_design.md`)

---

## Future Work

### Phase 9: Optimizations
- [ ] `lastTimeOtherDeviceWasActive` logic for conditional realtime
- [ ] GRDB `ValueObservation` for reactive UI updates

### Phase 10: Advanced Features
- [ ] Dead letter queue for failed items
- [ ] Retry logic with configurable max attempts
- [ ] Conflict resolution callbacks (custom merge strategies)

### Phase 11: SwiftUI Example App
- [ ] Full SwiftUI app demonstrating Syncable integration
- [ ] MVVM architecture with sync-aware ViewModels
- [ ] Network status indicator in UI

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
| Push sync (dirty detection via syncedAt) | ✅ |
| Pull sync with LWW | ✅ |
| ExponentialBackoff | ✅ |
| NetworkMonitor | ✅ |
| Background Sync Loop | ✅ |
| Realtime Subscriptions | ✅ |
| Echo Prevention Cache | ✅ |
| CLI Demo (SyncableDemo) | ✅ |
| Comprehensive README | ✅ |
| Unit tests | ✅ |
| technical_design.md | ✅ |
| roadmap.md | ✅ |
