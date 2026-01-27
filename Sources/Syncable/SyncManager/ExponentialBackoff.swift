import Foundation

/// Manages exponential backoff delays for retry logic.
///
/// Use this to implement retry strategies that progressively increase
/// delays between attempts, reducing load on failing services.
///
/// ## Usage
/// ```swift
/// var backoff = ExponentialBackoff()
///
/// while shouldRetry {
///     do {
///         try await performOperation()
///         backoff.reset()
///     } catch {
///         let delay = backoff.recordFailure()
///         try await Task.sleep(for: .seconds(delay))
///     }
/// }
/// ```
struct ExponentialBackoff: Sendable {
    private(set) var currentDelay: TimeInterval
    let maxDelay: TimeInterval
    let initialDelay: TimeInterval

    /// Create a new backoff tracker
    /// - Parameters:
    ///   - initialDelay: Starting delay in seconds (default: 1.0)
    ///   - maxDelay: Maximum delay cap in seconds (default: 60.0)
    init(initialDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 60.0) {
        self.initialDelay = initialDelay
        self.currentDelay = initialDelay
        self.maxDelay = maxDelay
    }

    /// Record a failure and return the delay to wait before retrying.
    /// Each call doubles the delay (up to maxDelay).
    /// - Returns: The delay to wait before the next retry attempt
    @discardableResult
    mutating func recordFailure() -> TimeInterval {
        let delay = currentDelay
        currentDelay = min(currentDelay * 2, maxDelay)
        return delay
    }

    /// Reset the backoff to the initial delay (call after success)
    mutating func reset() {
        currentDelay = initialDelay
    }
}
