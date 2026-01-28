import Foundation

/// Tracks recently pushed record IDs to prevent echo (re-syncing own changes).
///
/// When a record is pushed to Supabase, the realtime subscription will notify us
/// of the change. Without echo prevention, we would pull the same record back
/// immediately, wasting bandwidth and potentially causing sync loops.
///
/// ## Thread Safety
/// This is a reference type (class) to ensure mutations persist when used within
/// lock-protected code blocks. Struct value semantics would cause mutations to
/// only affect copies, breaking echo prevention.
///
/// ## Usage
/// ```swift
/// let cache = EchoPreventionCache(ttl: 60.0)
///
/// // After pushing a record
/// cache.markAsPushed(record.id)
///
/// // When receiving realtime notification
/// if cache.wasRecentlyPushed(recordId) {
///     // Skip - this is our own change echoing back
///     return
/// }
/// // Pull the change
/// ```
public final class EchoPreventionCache: @unchecked Sendable {
    private var cache: [UUID: Date] = [:]

    /// Time-to-live for cached entries in seconds
    public let ttl: TimeInterval

    /// Create a new echo prevention cache
    /// - Parameter ttl: How long to remember pushed IDs (default: 60 seconds)
    public init(ttl: TimeInterval = 60.0) {
        self.ttl = ttl
    }

    /// Number of IDs currently in the cache
    public var count: Int { cache.count }

    /// Mark a record ID as recently pushed to Supabase
    /// - Parameter id: The record's ID
    ///
    /// Also purges expired entries lazily to prevent unbounded cache growth.
    public func markAsPushed(_ id: UUID) {
        purgeExpired()
        cache[id] = Date()
    }

    /// Check if a record ID was recently pushed (within TTL)
    /// - Parameter id: The record's ID
    /// - Returns: true if this ID was pushed recently and should be ignored on pull
    public func wasRecentlyPushed(_ id: UUID) -> Bool {
        guard let pushedAt = cache[id] else { return false }
        return Date().timeIntervalSince(pushedAt) < ttl
    }

    /// Remove expired entries from the cache
    public func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-ttl)
        cache = cache.filter { $0.value > cutoff }
    }

    /// Clear all entries from the cache
    public func clear() {
        cache.removeAll()
    }
}
