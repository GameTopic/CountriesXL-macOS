import Foundation

enum SavedItemKind: String, Codable, CaseIterable, Identifiable {
    case resource
    case media
    case thread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resource: return "Resources"
        case .media: return "Media"
        case .thread: return "Threads"
        }
    }

    var systemImage: String {
        switch self {
        case .resource: return "shippingbox"
        case .media: return "photo.on.rectangle.angled"
        case .thread: return "text.bubble"
        }
    }
}

struct SavedItem: Identifiable, Codable, Hashable {
    let kind: SavedItemKind
    let sourceID: Int
    var title: String
    var subtitle: String?
    var detail: String?
    var imageURL: URL?
    var targetURL: URL?
    var mediaURL: URL?
    var savedAt: Date

    var id: String { "\(kind.rawValue)-\(sourceID)" }
    var shareURL: URL? { targetURL ?? mediaURL }

    init(
        kind: SavedItemKind,
        sourceID: Int,
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        imageURL: URL? = nil,
        targetURL: URL? = nil,
        mediaURL: URL? = nil,
        savedAt: Date = Date()
    ) {
        self.kind = kind
        self.sourceID = sourceID
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.imageURL = imageURL
        self.targetURL = targetURL
        self.mediaURL = mediaURL
        self.savedAt = savedAt
    }

    init(resource: XFResource) {
        self.init(
            kind: .resource,
            sourceID: resource.id,
            title: resource.title,
            subtitle: resource.category ?? resource.authorName,
            detail: resource.tagLine ?? resource.summary,
            imageURL: resource.iconURL ?? resource.coverURL,
            targetURL: resource.viewURL
        )
    }

    init(media: XFMedia) {
        self.init(
            kind: .media,
            sourceID: media.id,
            title: media.title,
            subtitle: media.username ?? media.categoryTitle ?? media.mediaURL.host,
            detail: media.description,
            imageURL: media.thumbnailURL,
            targetURL: media.viewURL,
            mediaURL: media.mediaURL
        )
    }

    init(thread: XFThread) {
        self.init(
            kind: .thread,
            sourceID: thread.id,
            title: thread.title,
            subtitle: "by \(thread.author)",
            detail: "\(thread.replyCount.formatted()) replies - \(thread.viewCount.formatted()) views",
            targetURL: URL(string: "https://cities-mods.com/threads/\(thread.id)/")
        )
    }

    var resource: XFResource {
        XFResource(
            id: sourceID,
            title: title,
            iconURL: imageURL,
            coverURL: nil,
            fileSize: nil,
            category: subtitle,
            rating: nil,
            ratingCount: nil,
            releaseDate: nil,
            updatedDate: nil,
            downloadCount: nil,
            viewCount: nil,
            tagLine: detail,
            versionString: nil,
            authorName: nil,
            summary: detail,
            descriptionBBCode: nil,
            installInstructions: nil,
            viewURL: targetURL,
            screenshots: [],
            fields: [],
            updates: [],
            reviews: [],
            videos: [],
            relatedResources: [],
            attachmentURLs: [:]
        )
    }

    var media: XFMedia? {
        guard let mediaURL = mediaURL ?? targetURL else { return nil }

        return XFMedia(
            id: sourceID,
            title: title,
            mediaURL: mediaURL,
            thumbnailURL: imageURL,
            viewURL: targetURL,
            description: detail,
            username: subtitle,
            mediaType: nil,
            categoryID: nil,
            categoryTitle: nil,
            albumID: nil,
            albumTitle: nil,
            viewCount: nil,
            commentCount: nil,
            reactionScore: nil,
            postedDate: nil,
            updatedDate: nil
        )
    }

    var thread: XFThread {
        XFThread(
            id: sourceID,
            title: title,
            author: subtitle?.replacingOccurrences(of: "by ", with: "") ?? "Unknown",
            replyCount: 0,
            viewCount: 0,
            nodeID: nil,
            userID: nil,
            postDate: nil
        )
    }
}
