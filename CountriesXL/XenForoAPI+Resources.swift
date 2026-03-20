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

        // Try decode known wrapper first.
        if let decoded = try? decoder.decode(ResourcesResponse.self, from: data), let list = decoded.resources {
            return list.map(resource(from:))
        }

        // Fallback: try to decode array directly.
        if let list = try? decoder.decode([ResourceDTO].self, from: data) {
            return list.map(resource(from:))
        }

        throw APIError.decodingFailed(NSError(domain: "XenForoAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode resources payload"]))
    }

    func fetchResourceDetail(id: Int, accessToken: String?) async throws -> XFResource {
        let req = try request(path: "resources/\(id)", accessToken: accessToken)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let decodedResource = (try? decoder.decode(SingleResponse<XFResource>.self, from: data).data)
            ?? (try? decoder.decode(XFResource.self, from: data))
        let raw = rootResourceDictionary(from: data)

        guard let raw else {
            if let decodedResource {
                return decodedResource
            }
            throw APIError.decodingFailed(NSError(domain: "XenForoAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to decode resource detail payload"]))
        }

        var merged = merge(resource: decodedResource ?? XFResource(id: id, title: string(in: raw, keys: ["title"]) ?? "Resource"), with: raw)

        let supplementalUpdates = try await fetchSupplementalResourceUpdates(resourceID: id, accessToken: accessToken)
        if !supplementalUpdates.isEmpty {
            let existingIDs = Set(merged.updates.map(\.id))
            let mergedUpdates = merged.updates + supplementalUpdates.filter { !existingIDs.contains($0.id) }
            if !mergedUpdates.isEmpty {
                merged.updates = mergedUpdates.sorted {
                    ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
                }
            }
        }

        return merged
    }

    private func resource(from dto: ResourceDTO) -> XFResource {
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

    private func rootResourceDictionary(from data: Data) -> [String: Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let raw = json as? [String: Any] {
            if let data = raw["data"] as? [String: Any] {
                if let resource = data["resource"] as? [String: Any] {
                    return data.merging(resource) { current, _ in current }
                }
                return data
            }

            if let resource = raw["resource"] as? [String: Any] {
                return raw.merging(resource) { current, _ in current }
            }

            return raw
        }

        return nil
    }

    private func merge(resource: XFResource, with raw: [String: Any]) -> XFResource {
        var merged = resource
        merged.title = string(in: raw, keys: ["title"]) ?? merged.title
        merged.iconURL = url(in: raw, keys: ["icon_url", "iconURL"]) ?? merged.iconURL
        merged.coverURL = url(in: raw, keys: ["cover_url", "coverURL", "thumbnail_url"]) ?? merged.coverURL
        merged.fileSize = int(in: raw, keys: ["file_size", "size", "fileSize"]) ?? merged.fileSize
        merged.category = string(in: raw, keys: ["category_title", "category"]) ?? merged.category
        merged.rating = double(in: raw, keys: ["rating_avg", "rating"]) ?? merged.rating
        merged.ratingCount = int(in: raw, keys: ["rating_count"]) ?? merged.ratingCount
        merged.releaseDate = date(in: raw, keys: ["release_date"]) ?? merged.releaseDate
        merged.updatedDate = date(in: raw, keys: ["last_update", "update_date", "updated_date"]) ?? merged.updatedDate
        merged.downloadCount = int(in: raw, keys: ["download_count"]) ?? merged.downloadCount
        merged.viewCount = int(in: raw, keys: ["view_count"]) ?? merged.viewCount
        merged.tagLine = string(in: raw, keys: ["tagline", "tag_line"]) ?? merged.tagLine
        merged.versionString = string(in: raw, keys: ["version_string", "version"]) ?? merged.versionString
        merged.authorName = string(in: raw, keys: ["username", "author", "author_name"]) ?? merged.authorName
        merged.summary = string(in: raw, keys: ["description", "summary", "tagline"]) ?? merged.summary
        merged.descriptionBBCode = string(in: raw, keys: ["message", "description_bbcode", "description"]) ?? merged.descriptionBBCode
        merged.installInstructions = installInstructions(in: raw) ?? merged.installInstructions
        merged.viewURL = url(in: raw, keys: ["view_url", "resource_url"]) ?? merged.viewURL

        let attachmentLookup = attachmentURLLookup(in: raw)
        if !attachmentLookup.isEmpty {
            merged.attachmentURLs = attachmentLookup
        }

        let screenshotURLs = screenshotURLs(in: raw, description: merged.descriptionBBCode)
        if !screenshotURLs.isEmpty {
            merged.screenshots = screenshotURLs
        }

        let resourceFields = fields(in: raw)
        if !resourceFields.isEmpty {
            merged.fields = resourceFields
        }

        let updateItems = updates(in: raw)
        if !updateItems.isEmpty {
            merged.updates = updateItems
        }

        let reviewItems = reviews(in: raw)
        if !reviewItems.isEmpty {
            merged.reviews = reviewItems
        }

        let videoItems = videos(in: raw, description: merged.descriptionBBCode)
        if !videoItems.isEmpty {
            merged.videos = videoItems
        }

        let related = relatedResources(in: raw)
        if !related.isEmpty {
            merged.relatedResources = related
        }

        return merged
    }

    private func fields(in raw: [String: Any]) -> [XFResourceField] {
        let attachmentLookup = attachmentURLLookup(in: raw)

        if let array = firstArray(in: raw, keys: ["fields", "resource_fields", "custom_fields"]) {
            let items = array.compactMap { item -> XFResourceField? in
                guard let dict = item as? [String: Any] else { return nil }
                let key = string(in: dict, keys: ["field_id", "key", "id"]) ?? UUID().uuidString
                let title = string(in: dict, keys: ["title", "field_name", "display_name", "label", "name"]) ?? prettify(key: key)
                let value = string(in: dict, keys: ["value", "display_value", "text"]) ?? ""
                guard !value.isEmpty else { return nil }
                let fieldImageURLs = fieldImageURLs(in: dict, value: value, attachmentLookup: attachmentLookup)
                return XFResourceField(
                    key: key,
                    title: title,
                    value: value,
                    displayLocation: string(in: dict, keys: ["display_location", "displayLocation", "display_group"]),
                    ownTabTitle: string(in: dict, keys: ["own_tab_name", "tab_title", "display_tab"]),
                    description: string(in: dict, keys: ["description", "hint", "explain"]),
                    displayOrder: int(in: dict, keys: ["display_order", "displayOrder"]),
                    imageURLs: fieldImageURLs
                )
            }
            if !items.isEmpty { return items.sorted(by: fieldSort) }
        }

        if let dict = firstDictionary(in: raw, keys: ["fields", "resource_fields", "custom_fields"]) {
            return dict.compactMap { key, value -> XFResourceField? in
                let valueDictionary = value as? [String: Any]
                let displayValue = string(in: valueDictionary ?? [:], keys: ["value", "display_value", "text", "content"]) ?? stringify(value)
                guard !displayValue.isEmpty else { return nil }
                return XFResourceField(
                    key: key,
                    title: string(in: valueDictionary ?? [:], keys: ["title", "field_name", "display_name", "label", "name"]) ?? prettify(key: key),
                    value: displayValue,
                    displayLocation: string(in: valueDictionary ?? [:], keys: ["display_location", "displayLocation", "display_group"]),
                    ownTabTitle: string(in: valueDictionary ?? [:], keys: ["own_tab_name", "tab_title", "display_tab"]),
                    description: string(in: valueDictionary ?? [:], keys: ["description", "hint", "explain"]),
                    displayOrder: int(in: valueDictionary ?? [:], keys: ["display_order", "displayOrder"]),
                    imageURLs: fieldImageURLs(in: valueDictionary ?? [:], value: displayValue, attachmentLookup: attachmentLookup)
                )
            }
            .sorted(by: fieldSort)
        }

        return []
    }

    private func updates(in raw: [String: Any]) -> [XFResourceUpdate] {
        guard let array = firstArray(in: raw, keys: ["updates", "resource_updates"]) else { return [] }

        return array.enumerated().compactMap { index, item in
            guard let dict = item as? [String: Any] else { return nil }
            return resourceUpdate(from: dict, fallbackIndex: index)
        }
    }

    private func reviews(in raw: [String: Any]) -> [XFResourceReview] {
        guard let array = firstArray(in: raw, keys: ["reviews", "ratings"]) else { return [] }

        return array.enumerated().compactMap { index, item in
            guard let dict = item as? [String: Any] else { return nil }
            let message = string(in: dict, keys: ["message", "review", "comment", "rating_comment"]) ?? ""
            let author = string(in: dict, keys: ["username", "author", "user"]) ?? "Member"
            return XFResourceReview(
                id: int(in: dict, keys: ["rating_id", "review_id", "id"]) ?? index,
                author: author,
                title: string(in: dict, keys: ["title"]),
                message: message,
                rating: double(in: dict, keys: ["rating", "score"]),
                date: date(in: dict, keys: ["rating_date", "review_date", "date", "post_date"])
            )
        }
    }

    private func videos(in raw: [String: Any], description: String?) -> [XFResourceVideo] {
        var urls = Set<URL>()
        var items: [XFResourceVideo] = []

        if let array = firstArray(in: raw, keys: ["videos", "video_urls"]) {
            for item in array {
                if let dict = item as? [String: Any],
                   let url = url(in: dict, keys: ["url", "video_url", "link"]) {
                    let title = string(in: dict, keys: ["title", "label"]) ?? url.absoluteString
                    if urls.insert(url).inserted {
                        items.append(XFResourceVideo(title: title, url: url))
                    }
                } else if let urlString = item as? String, let url = URL(string: urlString), urls.insert(url).inserted {
                    items.append(XFResourceVideo(title: url.absoluteString, url: url))
                }
            }
        }

        if let description {
            for embed in BBCodeParser.extractEmbeds(from: description, attachmentLookup: attachmentURLLookup(in: raw)) {
                switch embed.kind {
                case .youtube:
                    if let url = URL(string: "https://www.youtube.com/watch?v=\(embed.identifier)"),
                       urls.insert(url).inserted {
                        items.append(XFResourceVideo(title: "YouTube", url: url))
                    }
                case .facebook, .vimeo, .dailymotion, .streamable, .twitch, .directVideo, .url:
                    if let url = embed.url, urls.insert(url).inserted {
                        items.append(XFResourceVideo(title: url.host ?? url.absoluteString, url: url))
                    }
                default:
                    continue
                }
            }
        }

        return items
    }

    private func relatedResources(in raw: [String: Any]) -> [XFResource] {
        guard let array = firstArray(in: raw, keys: ["related_resources", "related"]) else { return [] }

        return array.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            return XFResource(
                id: int(in: dict, keys: ["resource_id", "id"]) ?? 0,
                title: string(in: dict, keys: ["title"]) ?? "Related Resource",
                iconURL: url(in: dict, keys: ["icon_url"]),
                coverURL: url(in: dict, keys: ["cover_url"]),
                fileSize: int(in: dict, keys: ["file_size"]),
                category: string(in: dict, keys: ["category_title", "category"]),
                rating: double(in: dict, keys: ["rating_avg", "rating"]),
                ratingCount: int(in: dict, keys: ["rating_count"]),
                releaseDate: date(in: dict, keys: ["release_date"]),
                updatedDate: date(in: dict, keys: ["update_date", "last_update"]),
                downloadCount: int(in: dict, keys: ["download_count"]),
                viewCount: int(in: dict, keys: ["view_count"]),
                tagLine: string(in: dict, keys: ["tagline", "tag_line"]),
                versionString: string(in: dict, keys: ["version_string", "version"]),
                authorName: string(in: dict, keys: ["username", "author"]),
                summary: string(in: dict, keys: ["description", "summary"]),
                descriptionBBCode: string(in: dict, keys: ["message", "description"]),
                installInstructions: installInstructions(in: dict),
                viewURL: url(in: dict, keys: ["view_url", "resource_url"])
            )
        }
        .filter { $0.id != 0 }
    }

    private func screenshotURLs(in raw: [String: Any], description: String?) -> [URL] {
        var collectedURLs = Set<URL>()
        let attachmentLookup = attachmentURLLookup(in: raw)

        for key in ["screenshots", "screenshot_urls", "attachments", "gallery", "images"] {
            guard let value = raw[key] else { continue }
            for url in urls(from: value) {
                collectedURLs.insert(url)
            }
        }

        if let description {
            let matches = description.matches(for: #"\[img\](.*?)\[/img\]"#)
            for match in matches {
                if let url = URL(string: match) {
                    collectedURLs.insert(url)
                }
            }

            for id in attachmentIDs(in: description) {
                if let url = attachmentLookup[id] {
                    collectedURLs.insert(url)
                }
            }
        }

        return Array(collectedURLs)
    }

    private func installInstructions(in raw: [String: Any]) -> String? {
        if let instructions = string(in: raw, keys: ["install_instructions", "installation", "how_to_install", "how_to_use"]) {
            return instructions
        }

        if let field = fields(in: raw).first(where: {
            let key = $0.key.lowercased()
            return key.contains("install") || key.contains("setup")
        }) {
            return field.value
        }

        return nil
    }

    private func firstArray(in raw: [String: Any], keys: [String]) -> [Any]? {
        for key in keys {
            if let array = raw[key] as? [Any] {
                return array
            }
        }
        return nil
    }

    private func firstDictionary(in raw: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let dict = raw[key] as? [String: Any] {
                return dict
            }
        }
        return nil
    }

    private func urls(from value: Any) -> [URL] {
        if let strings = value as? [String] {
            return strings.compactMap(URL.init(string:))
        }

        if let urls = value as? [URL] {
            return urls
        }

        if let dictionaries = value as? [[String: Any]] {
            return dictionaries.flatMap { preferredURLs(in: $0) }
        }

        if let value = value as? String, let url = URL(string: value) {
            return [url]
        }

        return []
    }

    private func attachmentURLLookup(in raw: [String: Any]) -> [String: URL] {
        var lookup: [String: URL] = [:]
        collectAttachmentURLs(from: raw, into: &lookup)
        return lookup
    }

    private func collectAttachmentURLs(from value: Any, into lookup: inout [String: URL]) {
        if let dict = value as? [String: Any] {
            if let resolvedURL = preferredURLs(in: dict).first,
               let id = int(in: dict, keys: ["attachment_id", "id", "media_id"]) {
                lookup[String(id)] = resolvedURL
            }

            for (key, nested) in dict {
                if let nestedDict = nested as? [String: Any],
                   let resolvedURL = preferredURLs(in: nestedDict).first {
                    lookup[key] = resolvedURL
                    if let id = int(in: nestedDict, keys: ["attachment_id", "id", "media_id"]) {
                        lookup[String(id)] = resolvedURL
                    }
                }
                collectAttachmentURLs(from: nested, into: &lookup)
            }
        } else if let array = value as? [Any] {
            for item in array {
                collectAttachmentURLs(from: item, into: &lookup)
            }
        }
    }

    private func fieldImageURLs(in raw: [String: Any], value: String, attachmentLookup: [String: URL]) -> [URL] {
        var collectedURLs = Set<URL>()

        for key in ["attachments", "images", "gallery", "screenshots"] {
            guard let value = raw[key] else { continue }
            for url in urls(from: value) {
                collectedURLs.insert(url)
            }
        }

        for id in attachmentIDs(in: value) {
            if let url = attachmentLookup[id] {
                collectedURLs.insert(url)
            }
        }

        for match in value.matches(for: #"\[img\](.*?)\[/img\]"#) {
            if let url = URL(string: match) {
                collectedURLs.insert(url)
            }
        }

        return Array(collectedURLs)
    }

    private func fetchSupplementalResourceUpdates(resourceID: Int, accessToken: String?) async throws -> [XFResourceUpdate] {
        let candidates: [(String, [URLQueryItem])] = [
            ("resources/\(resourceID)/updates", []),
            ("resource-updates", [URLQueryItem(name: "resource_id", value: String(resourceID))]),
            ("resource-versions", [URLQueryItem(name: "resource_id", value: String(resourceID))])
        ]

        for candidate in candidates {
            do {
                let request = try request(path: candidate.0, accessToken: accessToken, query: candidate.1)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else { continue }
                if let updates = supplementalUpdates(from: data), !updates.isEmpty {
                    return updates
                }
            } catch {
                continue
            }
        }

        return []
    }

    private func supplementalUpdates(from data: Data) -> [XFResourceUpdate]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let array = updateArray(from: json)
        guard !array.isEmpty else { return nil }
        return array.enumerated().compactMap { index, item in
            guard let dict = item as? [String: Any] else { return nil }
            return resourceUpdate(from: dict, fallbackIndex: index)
        }
    }

    private func updateArray(from json: Any) -> [Any] {
        if let array = json as? [Any] {
            return array
        }
        if let raw = json as? [String: Any] {
            if let data = raw["data"] {
                let nested = updateArray(from: data)
                if !nested.isEmpty { return nested }
            }
            for key in ["updates", "resource_updates", "versions", "resource_versions"] {
                if let array = raw[key] as? [Any] {
                    return array
                }
            }
        }
        return []
    }

    private func resourceUpdate(from dict: [String: Any], fallbackIndex: Int) -> XFResourceUpdate {
        let attachmentLookup = attachmentURLLookup(in: dict)
        let message = string(in: dict, keys: ["message", "description", "change_log", "content"]) ?? ""
        let images = updateImageURLs(in: dict, message: message, attachmentLookup: attachmentLookup)
        let videos = updateVideoURLs(in: dict, message: message, attachmentLookup: attachmentLookup)
        let title = string(in: dict, keys: ["title", "version_string", "version"]) ?? "Update \(fallbackIndex + 1)"

        return XFResourceUpdate(
            id: int(in: dict, keys: ["resource_update_id", "resource_version_id", "id"]) ?? fallbackIndex,
            title: title,
            versionString: string(in: dict, keys: ["version_string", "version", "version_id"]),
            message: message,
            date: date(in: dict, keys: ["date", "update_date", "post_date", "release_date"]),
            downloadURL: url(in: dict, keys: ["download_url", "release_download_url", "url", "view_url"]),
            attachmentURLs: attachmentLookup,
            imageURLs: images,
            videoURLs: videos
        )
    }

    private func updateImageURLs(in raw: [String: Any], message: String, attachmentLookup: [String: URL]) -> [URL] {
        var collected = Set<URL>()
        for key in ["attachments", "images", "gallery", "screenshots"] {
            guard let value = raw[key] else { continue }
            for url in urls(from: value) {
                collected.insert(url)
            }
        }
        for url in BBCodeParser.extractImageURLs(from: message, attachmentLookup: attachmentLookup) {
            collected.insert(url)
        }
        return Array(collected)
    }

    private func updateVideoURLs(in raw: [String: Any], message: String, attachmentLookup: [String: URL]) -> [URL] {
        var collected = Set<URL>()
        if let array = firstArray(in: raw, keys: ["videos", "video_urls"]) {
            for item in array {
                if let dict = item as? [String: Any], let url = url(in: dict, keys: ["url", "video_url", "link"]) {
                    collected.insert(url)
                } else if let string = item as? String, let url = URL(string: string) {
                    collected.insert(url)
                }
            }
        }
        for embed in BBCodeParser.extractEmbeds(from: message, attachmentLookup: attachmentLookup) {
            if let url = embed.url {
                collected.insert(url)
            }
        }
        return Array(collected)
    }

    private func preferredURLs(in raw: [String: Any]) -> [URL] {
        let keys = [
            "full_url", "image_url", "original_url", "source_url",
            "direct_url", "attachment_url", "view_url", "url",
            "link", "thumbnail_url"
        ]
        var urls: [URL] = []
        var seen = Set<String>()
        for key in keys {
            if let url = url(in: raw, keys: [key]), seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private func attachmentIDs(in text: String) -> [String] {
        text.matches(for: #"(?i)\[attach[^\]]*\](\d+)\[/attach\]"#)
    }

    private func string(in raw: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = raw[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
            if let value = raw[key] as? NSString {
                let string = value as String
                if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return string
                }
            }
        }
        return nil
    }

    private func url(in raw: [String: Any], keys: [String]) -> URL? {
        for key in keys {
            if let url = raw[key] as? URL {
                return url
            }
            if let value = raw[key] as? String, let url = URL(string: value) {
                return url
            }
        }
        return nil
    }

    private func int(in raw: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = raw[key] as? Int { return value }
            if let value = raw[key] as? Double { return Int(value) }
            if let value = raw[key] as? String, let intValue = Int(value) { return intValue }
            if let value = raw[key] as? NSNumber { return value.intValue }
        }
        return nil
    }

    private func double(in raw: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = raw[key] as? Double { return value }
            if let value = raw[key] as? Int { return Double(value) }
            if let value = raw[key] as? String, let doubleValue = Double(value) { return doubleValue }
            if let value = raw[key] as? NSNumber { return value.doubleValue }
        }
        return nil
    }

    private func date(in raw: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = raw[key] as? TimeInterval {
                return Date(timeIntervalSince1970: value)
            }
            if let value = raw[key] as? Int {
                return Date(timeIntervalSince1970: TimeInterval(value))
            }
            if let value = raw[key] as? String, let interval = TimeInterval(value) {
                return Date(timeIntervalSince1970: interval)
            }
            if let value = raw[key] as? NSNumber {
                return Date(timeIntervalSince1970: value.doubleValue)
            }
        }
        return nil
    }

    private func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            return array.map(stringify).filter { !$0.isEmpty }.joined(separator: ", ")
        case let dict as [String: Any]:
            return dict
                .map { "\($0.key): \(stringify($0.value))" }
                .joined(separator: ", ")
        default:
            return ""
        }
    }

    private func prettify(key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var fieldSort: (XFResourceField, XFResourceField) -> Bool {
        { lhs, rhs in
            let leftOrder = lhs.displayOrder ?? .max
            let rightOrder = rhs.displayOrder ?? .max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

private extension String {
    func matches(for pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: self) else { return nil }
            return String(self[range])
        }
    }
}
