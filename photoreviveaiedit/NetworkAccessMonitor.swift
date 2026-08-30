import Combine
import Network

@MainActor
final class NetworkAccessMonitor: ObservableObject {
    @Published private(set) var hasUsableNetworkPath: Bool

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(
        label: "com.photorevival.network-access-monitor",
        qos: .userInitiated
    )

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        hasUsableNetworkPath = monitor.currentPath.status == .satisfied
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.hasUsableNetworkPath = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
