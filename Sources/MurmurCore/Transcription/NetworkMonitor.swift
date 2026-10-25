import Foundation
import Network

/// Tells whether the current connection is metered (mobile data, personal hotspot, Low Data Mode).
public final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var metered = false

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.metered = path.isExpensive || path.isConstrained
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "app.murmur.network-monitor"))
    }

    deinit { monitor.cancel() }

    public var isMetered: Bool {
        lock.lock(); defer { lock.unlock() }
        return metered
    }
}
