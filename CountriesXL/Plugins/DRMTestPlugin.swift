import Foundation

/// Small plugin-style helper to test DRM license server endpoints.
/// This is intentionally small and pluggable; it performs a lightweight probe that:
///  - GETs the license endpoint to ensure it's reachable
///  - Attempts to fetch a certificate candidate (optional)
///  - Returns a short status message
public enum DRMTestPlugin {
    public static func testLicenseServer(endpoint: URL) async throws -> String {
        // 1) Quick GET to endpoint
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // If body present, report size. Keep this minimal for a probe.
        if !data.isEmpty {
            return "Endpoint reachable (\(data.count) bytes returned)."
        }
        return "Endpoint reachable."
    }

    // Register presence so UI can discover this capability even when compiled in
    private static let _registered: Void = {
        PluginManager.shared.registerPresence(name: "DRMTestPlugin")
    }()
}
