import Foundation

extension XenForoAPI {
    struct ResourceDownloadLinkResponse: Decodable {
        let download_url: URL?
    }

    func resolvedResourceDownloadRequest(resourceID: Int, accessToken: String?) async throws -> URLRequest {
        let req = try resourceDownloadRequest(resourceID: resourceID, accessToken: accessToken)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }

        if let decoded = try? JSONDecoder().decode(ResourceDownloadLinkResponse.self, from: data),
           let url = decoded.download_url {
            return URLRequest(url: url)
        }

        if let location = http.value(forHTTPHeaderField: "Location"),
           let url = URL(string: location) {
            return URLRequest(url: url)
        }

        if let mimeType = http.mimeType, mimeType != "application/json", mimeType != "text/html" {
            return req
        }

        return req
    }

    func resourceDownloadRequest(resourceID: Int, accessToken: String?) throws -> URLRequest {
        var req = try request(path: "resources/\(resourceID)/download", accessToken: accessToken)
        req.setValue("application/octet-stream,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        return req
    }

    func resourceDownloadURL(resourceID: Int, accessToken: String?) async throws -> URL {
        // Common pattern: GET /resources/{id}/download (or an API that returns a signed URL)
        let req = try resourceDownloadRequest(resourceID: resourceID, accessToken: accessToken)
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
