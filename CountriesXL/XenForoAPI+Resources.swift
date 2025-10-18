import Foundation

extension XenForoAPI {
    struct ResourcesResponse: Decodable {
        let resources: [ResourceDTO]?
    }

    struct ResourceDTO: Decodable {
        let resource_id: Int
        let title: String
        let icon_url: URL?
        let cover_url: URL?
        let file_size: Int?
        let category_title: String?
        let rating_avg: Double?
        let rating_count: Int?
        let release_date: TimeInterval?
        let last_update: TimeInterval?
        let download_count: Int?
        let view_count: Int?
        let tagline: String?
    }

    func fetchResources(accessToken: String?) async throws -> [XFResource] {
        var req = request(path: "resources")
        if let token = accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }
        // Try decode known wrapper
        if let decoded = try? JSONDecoder().decode(ResourcesResponse.self, from: data), let list = decoded.resources {
            return list.map { dto in
                XFResource(
                    id: dto.resource_id,
                    title: dto.title,
                    iconURL: dto.icon_url,
                    coverURL: dto.cover_url,
                    fileSize: dto.file_size,
                    category: dto.category_title,
                    rating: dto.rating_avg,
                    ratingCount: dto.rating_count,
                    releaseDate: dto.release_date.map { Date(timeIntervalSince1970: $0) },
                    updatedDate: dto.last_update.map { Date(timeIntervalSince1970: $0) },
                    downloadCount: dto.download_count,
                    viewCount: dto.view_count,
                    tagLine: dto.tagline
                )
            }
        }
        // Fallback: try to decode array directly
        if let list = try? JSONDecoder().decode([ResourceDTO].self, from: data) {
            return list.map { dto in
                XFResource(
                    id: dto.resource_id,
                    title: dto.title,
                    iconURL: dto.icon_url,
                    coverURL: dto.cover_url,
                    fileSize: dto.file_size,
                    category: dto.category_title,
                    rating: dto.rating_avg,
                    ratingCount: dto.rating_count,
                    releaseDate: dto.release_date.map { Date(timeIntervalSince1970: $0) },
                    updatedDate: dto.last_update.map { Date(timeIntervalSince1970: $0) },
                    downloadCount: dto.download_count,
                    viewCount: dto.view_count,
                    tagLine: dto.tagline
                )
            }
        }
        throw APIError.decodingFailed
    }
}
