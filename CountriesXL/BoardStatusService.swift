import Foundation
import Combine

@MainActor
final class BoardStatusService: ObservableObject {
    static let shared = BoardStatusService()

    @Published var isActive: Bool = true
    @Published var versionString: String = ""
    @Published var isXF23OrNewer: Bool = false
    @Published var lastChecked: Date? = nil
    @Published var lastError: String? = nil

    func refresh() async {
        let apiURLs = [
            URL(string: "https://cities-mods.com/api/")!,
            URL(string: "https://cities-mods.com/")!
        ]
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)

        var active = false
        var version: String = ""
        var lastErr: String? = nil

        for url in apiURLs {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                if (200..<400).contains(http.statusCode) {
                    active = true
                    if let powered = http.value(forHTTPHeaderField: "X-Powered-By"), powered.lowercased().contains("xenforo") {
                        version = version.isEmpty ? powered : version
                    }
                    if version.isEmpty, let server = http.value(forHTTPHeaderField: "Server"), server.lowercased().contains("xenforo") {
                        version = server
                    }
                    if version.isEmpty, data.count > 0, let html = String(data: data, encoding: .utf8) {
                        if let genRange = html.range(of: "<meta name=\"generator\" content=\"XenForo", options: [.caseInsensitive]) {
                            let suffix = html[genRange.lowerBound...]
                            if let end = suffix.firstIndex(of: ">") {
                                let meta = String(suffix[..<end])
                                if let verStart = meta.range(of: "XenForo ")?.upperBound {
                                    let ver = meta[verStart...].replacingOccurrences(of: "\"", with: "")
                                    version = String(ver)
                                }
                            }
                        }
                    }
                    break
                } else {
                    // Localized HTTP status message (e.g. "HTTP status: 404")
                    lastErr = String(format: NSLocalizedString("board.status.http_status_fmt", comment: "HTTP status message with code"), http.statusCode)
                }
            } catch {
                // Preserve underlying error description as detail (already localized by Foundation)
                lastErr = (error as NSError).localizedDescription
                continue
            }
        }

        let is23 = Self.isVersionAtLeast(version, major: 2, minor: 3)
        await MainActor.run {
            self.isActive = active
            self.versionString = version
            self.isXF23OrNewer = is23
            self.lastChecked = Date()
            // Use localized fallback for unknown error
            self.lastError = active ? nil : (lastErr ?? NSLocalizedString("board.status.unknown_error", comment: "Fallback unknown error text"))
        }
    }

    private static func isVersionAtLeast(_ s: String, major: Int, minor: Int) -> Bool {
        // Extract first occurrence of something like 2.3 or 2.3.1
        // Attempt to find a version pattern in the string (e.g. 2.3.1)
        let pattern = #"(\d+)\.(\d+)(?:\.(\d+))?"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            if let match = regex.firstMatch(in: s, options: [], range: range) {
                if let majorRange = Range(match.range(at: 1), in: s),
                   let minorRange = Range(match.range(at: 2), in: s) {
                    let majorVal = Int(s[majorRange]) ?? 0
                    let minorVal = Int(s[minorRange]) ?? 0
                    if majorVal > major { return true }
                    if majorVal == major && minorVal >= minor { return true }
                }
            }
        }
        return false
    }
}
