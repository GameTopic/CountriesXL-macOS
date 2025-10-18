import Foundation

extension XenForoAPI {
    struct ResourceDownloadLinkResponse: Decodable {
        let download_url: URL?
    }

    func resourceDownloadURL(resourceID: Int, accessToken: String?) async throws -> URL {
        // Common pattern: GET /resources/{id}/download (or an API that returns a signed URL)
        var req = request(path: "resources/\(resourceID)/download")
        if let token = accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }
        if let decoded = try? JSONDecoder().decode(ResourceDownloadLinkResponse.self, from: data), let url = decoded.download_url {
            return url
        }
        // Fallback: if API returns the file directly via redirect or attachment, attempt to parse Location header
        if let location = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"), let url = URL(string: location) {
            return url
        }
        // As a last resort, assume direct download from this endpoint
        return baseURL.appendingPathComponent("resources/\(resourceID)/download")
    }
}
