# Contributing to Syncable-Swift

## Development Environment

We use standard Swift Package Manager tooling.

### Common Tasks

- **Build**: `swift build`
- **Test**: `swift test`
- **Clean**: `swift package clean`

## Code Generation vs. Swift

Coming from Flutter/Dart? You might be used to running `just generate-code` for JSON serialization (`freezed`/`json_serializable`) or mocks (`mockito`).

**In Swift, we generally don't need this step:**

1.  **Serialization**: Swift's `Codable` protocol is synthesized automatically by the compiler. You don't need to generate code to convert your models to/from JSON.
2.  **Mocks**: We prefer **real in-memory databases** (via GRDB) over mocking the database layer. This ensures our sync logic works with the actual SQLite engine.
    - See `Tests/SyncableTests/SyncableProtocolTests.swift` for examples of `makeTestDatabase()`.
3.  **Use Cases**: If we eventually need complex mocks, we might introduce a tool like Sourcery, but for now, the project relies on protocol-based design and integration tests.

## Testing Strategy

We use **Swift Testing** (macros) and **XCTest**.

- **Unit Tests**: Focus on the logic within `SyncManager` and `SyncableProtocol`.
- **Integration Tests**: Use an in-memory `DatabaseQueue` to verify that data is actually persisted and queried correctly using GRDB.
