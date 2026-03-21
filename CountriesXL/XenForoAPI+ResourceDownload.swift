import Foundation

extension XenForoAPI {
    struct ResourceDownloadLinkResponse: Decodable {
        let download_url: URL?
    }

    private struct ResourceDetailDownloadResponse: Decodable {
        let resource: ResourceDetailPayload
    }

    private struct ResourceDetailPayload: Decodable {
        let currentFiles: [CurrentFile]

        enum CodingKeys: String, CodingKey {
            case currentFiles = "current_files"
        }
    }

    private struct CurrentFile: Decodable {
        let id: Int
        let filename: String
        let size: Int?
        let downloadURL: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case filename
            case size
            case downloadURL = "download_url"
        }
    }

    func resolvedResourceDownloadRequest(resourceID: Int, accessToken: String?) async throws -> URLRequest {
        if let request = try await resourceFileRequestFromDetail(resourceID: resourceID, accessToken: accessToken) {
            return request
        }

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
        if let request = try await resourceFileRequestFromDetail(resourceID: resourceID, accessToken: accessToken),
           let url = request.url {
            return url
        }

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

    private func resourceFileRequestFromDetail(resourceID: Int, accessToken: String?) async throws -> URLRequest? {
        let detailRequest = try request(path: "resources/\(resourceID)", accessToken: accessToken)
        let (data, response) = try await URLSession.shared.data(for: detailRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(ResourceDetailDownloadResponse.self, from: data),
              let file = decoded.resource.currentFiles.first,
              let downloadURL = file.downloadURL else {
            return nil
        }

        return try authenticatedRequest(for: downloadURL, accessToken: accessToken)
    }

    private func authenticatedRequest(for url: URL, accessToken: String?) throws -> URLRequest {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return URLRequest(url: url)
        }

        let apiBasePrefix = baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path
        var path = components.path
        if path.hasPrefix(apiBasePrefix + "/") {
            path.removeFirst(apiBasePrefix.count + 1)
        } else if path == apiBasePrefix {
            path = ""
        } else if path.hasPrefix("/") {
            path.removeFirst()
        }

        let queryItems = components.queryItems ?? []
        var request = try self.request(path: path, accessToken: accessToken, query: queryItems)
        request.setValue("application/octet-stream,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }
}
