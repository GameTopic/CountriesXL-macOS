import Foundation
import SwiftUI

extension XenForoAPI {
    struct MediaGalleryPage {
        let items: [XFMedia]
        let pagination: Pagination?
    }

    func fetchMediaGalleryPage(page: Int = 1, accessToken: String? = nil) async throws -> MediaGalleryPage {
        let mediaPrefix = UserDefaults.standard.string(forKey: "xf_media_route_prefix") ?? "media"
        let query = [URLQueryItem(name: "page", value: String(page))]
        let req = try request(path: mediaPrefix, accessToken: accessToken, query: query)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let response: MediaEnvelopeListResponse<XFMedia>
        do {
            response = try decoder.decode(MediaEnvelopeListResponse<XFMedia>.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
        return MediaGalleryPage(items: response.media ?? [], pagination: response.pagination)
    }

    func fetchMediaGallery(page: Int = 1, accessToken: String? = nil) async throws -> [XFMedia] {
        try await fetchMediaGalleryPage(page: page, accessToken: accessToken).items
    }
}
