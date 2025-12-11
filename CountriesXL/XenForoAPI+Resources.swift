import Foundation

extension XenForoAPI {
    // DTOs matching potential resources payloads
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
        let release_date: Double?
        let last_update: Double?
        let download_count: Int?
        let view_count: Int?
        let tagline: String?
    }

    // Fetches resources and maps to XFResource using this file's DTOs.
    // Prefer the main client's listResources when possible, but keep this for compatibility.
    func fetchResources(accessToken: String?) async throws -> [XFResource] {
        let req = try request(path: "resources", accessToken: accessToken)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }

        let decoder = JSONDecoder()
        // Dates provided as seconds since epoch in Double
        // We'll manually map them below rather than using a date strategy

        // Try decode known wrapper first
        if let decoded = try? decoder.decode(ResourcesResponse.self, from: data), let list = decoded.resources {
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
        if let list = try? decoder.decode([ResourceDTO].self, from: data) {
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
        throw APIError.decodingFailed(NSError(domain: "XenForoAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode resources payload"]))
    }
}
