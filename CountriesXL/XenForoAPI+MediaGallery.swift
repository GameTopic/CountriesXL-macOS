import Foundation
import SwiftUI

extension XenForoAPI {
    struct MediaItemDTO: Decodable {
        let media_id: Int
        let title: String
        let description: String?
        let thumbnail_url: URL?
        let playback_urls: [String: String]? // e.g. { "hls": "https://...m3u8", "mp4": "https://...mp4" }
        let uploaded_date: TimeInterval?
    }

    struct MediaListResponse: Decodable {
        let media: [MediaItemDTO]?
        let total: Int?
    }

    func fetchMediaGallery(page: Int = 1, perPage: Int = 24, accessToken: String? = nil) async throws -> [XFMediaItem] {
        // Use route prefix if available
        let mediaPrefix = UserDefaults.standard.string(forKey: "xf_media_route_prefix") ?? "media"
        var req = request(path: "\(mediaPrefix)")
        // Add paging query parameters
        var comps = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: String(perPage))]
        req.url = comps.url
        if let token = accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }
        if let decoded = try? JSONDecoder().decode(MediaListResponse.self, from: data), let list = decoded.media {
            return list.map { dto in
                XFMediaItem(id: dto.media_id, title: dto.title, description: dto.description, thumbnailURL: dto.thumbnail_url, playbackCandidates: dto.playback_urls?.compactMapValues { URL(string: $0) } ?? [:], uploadedDate: dto.uploaded_date.map { Date(timeIntervalSince1970: $0) })
            }
        }
        // Fallback decode array
        if let list = try? JSONDecoder().decode([MediaItemDTO].self, from: data) {
            return list.map { dto in
                XFMediaItem(id: dto.media_id, title: dto.title, description: dto.description, thumbnailURL: dto.thumbnail_url, playbackCandidates: dto.playback_urls?.compactMapValues { URL(string: $0) } ?? [:], uploadedDate: dto.uploaded_date.map { Date(timeIntervalSince1970: $0) })
            }
        }
        throw APIError.decodingFailed
    }
}

// Lightweight model used by UI
struct XFMediaItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let description: String?
    let thumbnailURL: URL?
    let playbackCandidates: [String: URL] // keyed by type e.g. "hls", "mp4"
    let uploadedDate: Date?
}
