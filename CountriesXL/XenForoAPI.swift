import Foundation

// Minimal API client scaffold for XenForo 2.3+ REST API at cities-mods.com
struct XenForoAPI {
    let baseURL = URL(string: "https://cities-mods.com/api")!

    // Provided by user
    private let apiKey: String = "9VGBbWI1Cvlrfg6uEPHxJ5q3CUxoi-MJ"
    let loginURL = URL(string: "https://cities-mods.com/login")!
    let registerURL = URL(string: "https://cities-mods.com/register")!

    enum APIError: Error { case invalidResponse, serverError(Int), decodingFailed }

    // MARK: - Request Builder
    func request(path: String, accessToken: String? = nil, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        // XenForo API key header
        req.addValue(apiKey, forHTTPHeaderField: "XF-Api-Key")
        // Optional OAuth2 bearer (when available in future)
        if let token = accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    // Example: Fetch current user avatar URL (placeholder)
    func currentUserAvatarURL(accessToken: String?) async throws -> URL {
        // Placeholder: In real implementation, call /me to get avatar URLs
        return URL(string: "https://cities-mods.com/favicon.ico")!
    }

    // Example: Search (placeholder)
    func search(query: String, accessToken: String?) async throws -> SearchResults {
        let req = request(path: "search", accessToken: accessToken, query: [URLQueryItem(name: "q", value: query)])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.serverError(http.statusCode) }
        // TODO: decode real schema once wired to XenForo search endpoint
        _ = data
        return SearchResults(resources: [], threads: [], media: [], users: [])
    }
}

// MARK: - Models (placeholders)

struct XFResource: Identifiable, Codable, Hashable {
    var id: Int
    var title: String
    var iconURL: URL?
    var coverURL: URL?
    var fileSize: Int?
    var category: String?
    var rating: Double?
    var ratingCount: Int?
    var releaseDate: Date?
    var updatedDate: Date?
    var downloadCount: Int?
    var viewCount: Int?
    var tagLine: String?
}

struct XFThread: Identifiable, Codable, Hashable {
    var id: Int
    var title: String
    var author: String
    var replyCount: Int
    var viewCount: Int
}

struct XFMedia: Identifiable, Codable, Hashable {
    var id: Int
    var title: String
    var mediaURL: URL
    var thumbnailURL: URL?
}

struct XFUser: Identifiable, Codable, Hashable {
    var id: Int
    var username: String
    var avatarURL: URL?
}

struct SearchResults: Codable {
    var resources: [XFResource]
    var threads: [XFThread]
    var media: [XFMedia]
    var users: [XFUser]
}

