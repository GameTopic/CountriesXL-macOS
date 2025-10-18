import Foundation
import Network
import Combine

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("NetworkStatusChanged")
}

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    nonisolated static func handlePathUpdate(_ connected: Bool) {
        Task { @MainActor in
            NetworkMonitor.shared.isConnected = connected
            NotificationCenter.default.post(name: .networkStatusChanged, object: nil, userInfo: ["connected": connected])
        }
    }

    @Published var isConnected: Bool? = nil
    @Published var domainReachable: Bool? = nil
    @Published var lastError: String? = nil
    @Published var lastChecked: Date? = nil

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor.queue")
    private var started = false
    private var checkTask: Task<Void, Never>? = nil

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = (path.status == .satisfied)
            NetworkMonitor.handlePathUpdate(connected)
            Task { @MainActor [weak self] in
                self?.scheduleCheck()
            }
        }
        monitor.start(queue: queue)
        // Perform an initial check shortly after starting to allow currentPath to populate
        scheduleCheck(delay: 0.25)
    }

    func stop() {
        monitor.cancel()
        checkTask?.cancel()
        checkTask = nil
        started = false
    }

    private func scheduleCheck(delay: TimeInterval = 0.0) {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.checkNow()
        }
    }

    func checkNow() async {
        // Probe the specific domain to ensure our app-required backend is reachable
        let urls = [
            URL(string: "https://cities-mods.com/api/")!,
            URL(string: "https://cities-mods.com/")!
        ]
        var success = false
        var lastErr: String? = nil

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)

        for url in urls {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD" // Faster than GET for reachability
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                    success = true
                    break
                } else if let http = response as? HTTPURLResponse {
                    lastErr = "HTTP status: \(http.statusCode)"
                } else {
                    lastErr = "Invalid response"
                }
            } catch {
                lastErr = (error as NSError).localizedDescription
                continue
            }
        }

        await MainActor.run {
            self.domainReachable = success
            if let connected = self.isConnected {
                self.isConnected = connected && success // require both network and domain reachability
            } else {
                self.isConnected = success
            }
            self.lastError = success ? nil : (lastErr ?? "Unknown error")
            self.lastChecked = Date()
            // Broadcast consolidated status
            if let connected = self.isConnected {
                NotificationCenter.default.post(name: .networkStatusChanged, object: nil, userInfo: ["connected": connected, "domainReachable": success])
            }
        }
    }

    @MainActor
    deinit {
        stop()
    }
}
