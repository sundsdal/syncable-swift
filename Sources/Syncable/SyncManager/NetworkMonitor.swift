import Foundation
import Network

/// Monitors network connectivity and notifies when connectivity is restored.
///
/// Uses Apple's Network.framework for reliable connectivity detection.
/// Thread-safe for access from any thread.
///
/// ## Usage
/// ```swift
/// let monitor = NetworkMonitor()
/// monitor.start {
///     print("Network restored - sync now")
/// }
///
/// if monitor.isConnected {
///     // Perform network operation
/// }
///
/// // When done
/// monitor.stop()
/// ```
final class NetworkMonitor: @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "syncable.network-monitor")
    private let lock = NSLock()

    private var _isConnected: Bool = true
    private var _onConnectivityRestored: (() -> Void)?

    /// Whether the network is currently connected
    var isConnected: Bool {
        lock.withLock { _isConnected }
    }

    init() {
        self.monitor = NWPathMonitor()
    }

    /// Start monitoring network connectivity
    /// - Parameter onConnectivityRestored: Callback fired when connectivity changes from disconnected to connected
    func start(onConnectivityRestored: @escaping () -> Void) {
        lock.withLock { _onConnectivityRestored = onConnectivityRestored }

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let wasConnected = self.isConnected
            let nowConnected = path.status == .satisfied

            self.lock.withLock { self._isConnected = nowConnected }

            if !wasConnected && nowConnected {
                self.lock.withLock { self._onConnectivityRestored }?()
            }
        }
        monitor.start(queue: queue)
    }

    /// Stop monitoring network connectivity
    func stop() {
        monitor.cancel()
    }
}
