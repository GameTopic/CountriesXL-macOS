import Foundation

// Minimal API client scaffold for XenForo 2.3+ REST API at cities-mods.com
struct XenForoAPI {
    let baseURL = URL(string: "https://cities-mods.com/api")!

    // Provided by user (consider moving out of source for production)
    private let apiKey: String = "9VGBbWI1Cvlrfg6uEPHxJ5q3CUxoi-MJ"
    let loginURL = URL(string: "https://cities-mods.com/login")!
    let registerURL = URL(string: "https://cities-mods.com/register")!

    enum APIError: Error, LocalizedError { case invalidResponse, serverError(Int, Data?), decodingFailed(Error), badRequest
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response"
            case .serverError(let code, _): return "Server error: \(code)"
            case .decodingFailed(let err): return "Decoding failed: \(err.localizedDescription)"
            case .badRequest: return "Bad request (400). Check required parameters."
            }
        }
    }

    // MARK: - Request Builder
    enum HTTPMethod: String { case GET, POST, PUT, DELETE }

    func request(path: String,
                 method: HTTPMethod = .GET,
                 accessToken: String? = nil,
                 query: [URLQueryItem] = [],
                 body: Encodable? = nil,
                 formData: [String: String]? = nil) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method.rawValue
        // XenForo API key header
        req.addValue(apiKey, forHTTPHeaderField: "XF-Api-Key")
        // Optional OAuth2 bearer (when available in future)
        if let token = accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        if let form = formData { // URL-encoded form (for some POST endpoints)
            let bodyString = form.map { key, value in
                "\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }.sorted().joined(separator: "&")
            req.httpBody = bodyString.data(using: .utf8)
            req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        } else if let body = body {
            do {
                req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                throw APIError.decodingFailed(error)
            }
        }
        return req
    }

    // MARK: - Transport
    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type = T.self) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 400 { throw APIError.badRequest }
            throw APIError.serverError(http.statusCode, data)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    // MARK: - Paged results helper
    struct PagedResult<Item: Decodable>: Decodable {
        let items: [Item]
        let page: Int?
        let perPage: Int?
        let total: Int?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // support decoding from ListResponse shape
            if let data = try? c.decode([Item].self, forKey: .items) {
                items = data
            } else {
                // fallback if top-level decoding is used directly
                items = []
            }
            page = try? c.decode(Int.self, forKey: .page)
            perPage = try? c.decode(Int.self, forKey: .perPage)
            total = try? c.decode(Int.self, forKey: .total)
        }
        private enum CodingKeys: String, CodingKey { case items = "data", page, perPage, total }
    }

    // MARK: - Common wrappers
    struct ListResponse<T: Decodable>: Decodable { let data: [T]?; let pagination: Pagination? }
    struct SingleResponse<T: Decodable>: Decodable { let data: T }
    struct Pagination: Decodable { let page: Int?; let perPage: Int?; let total: Int? }
    struct Paged<T: Decodable> { let items: [T]; let pagination: Pagination? }

    // MARK: - Site index
    struct SiteIndex: Decodable { let version_id: Int; let site_title: String; let base_url: String; let api_url: String }
    func index() async throws -> SiteIndex {
        let req = try request(path: "index")
        return try await send(req, as: SiteIndex.self)
    }

    // MARK: - Me
    struct MeResponse: Decodable { let me: XFUser }
    func me(accessToken: String? = nil) async throws -> XFUser {
        let req = try request(path: "me", accessToken: accessToken)
        let res: MeResponse = try await send(req)
        return res.me
    }

    func updateMe(options: [String: String] = [:], profile: [String: String] = [:], privacy: [String: String] = [:], other: [String: String] = [:], accessToken: String? = nil) async throws {
        var form: [String: String] = [:]
        options.forEach { form["option[\($0.key)]"] = $0.value }
        profile.forEach { form["profile[\($0.key)]"] = $0.value }
        privacy.forEach { form["privacy[\($0.key)]"] = $0.value }
        other.forEach { form[$0.key] = $0.value }
        let req = try request(path: "me", method: .POST, accessToken: accessToken, formData: form)
        struct Success: Decodable { let success: Bool }
        _ = try await send(req, as: Success.self)
    }

    // MARK: - Avatar helpers
    func currentUserAvatarURL(accessToken: String?) async throws -> URL {
        let user = try await me(accessToken: accessToken)
        if let url = user.avatarURL { return url }
        return URL(string: "https://cities-mods.com/favicon.ico")!
    }

    // MARK: - Resources
    func listResources(page: Int? = nil, category: Int? = nil, accessToken: String? = nil) async throws -> Paged<XFResource> {
        var q: [URLQueryItem] = []
        if let page = page { q.append(URLQueryItem(name: "page", value: String(page))) }
        if let category = category { q.append(URLQueryItem(name: "category_id", value: String(category))) }
        let req = try request(path: "resources", accessToken: accessToken, query: q)
        let res: ListResponse<XFResource> = try await send(req)
        return Paged(items: res.data ?? [], pagination: res.pagination)
    }

    func getResource(id: Int, accessToken: String? = nil) async throws -> XFResource {
        let req = try request(path: "resources/\(id)", accessToken: accessToken)
        let res: SingleResponse<XFResource> = try await send(req)
        return res.data
    }

    // MARK: - Media
    func listMedia(page: Int? = nil, category: Int? = nil, accessToken: String? = nil) async throws -> Paged<XFMedia> {
        var q: [URLQueryItem] = []
        if let page = page { q.append(URLQueryItem(name: "page", value: String(page))) }
        if let category = category { q.append(URLQueryItem(name: "category_id", value: String(category))) }
        let req = try request(path: "media", accessToken: accessToken, query: q)
        let res: ListResponse<XFMedia> = try await send(req)
        return Paged(items: res.data ?? [], pagination: res.pagination)
    }

    func getMedia(id: Int, accessToken: String? = nil) async throws -> XFMedia {
        let req = try request(path: "media/\(id)", accessToken: accessToken)
        let res: SingleResponse<XFMedia> = try await send(req)
        return res.data
    }

    // MARK: - Threads
    func listThreads(nodeID: Int? = nil, page: Int? = nil, accessToken: String? = nil) async throws -> Paged<XFThread> {
        var q: [URLQueryItem] = []
        if let nodeID = nodeID { q.append(URLQueryItem(name: "node_id", value: String(nodeID))) }
        if let page = page { q.append(URLQueryItem(name: "page", value: String(page))) }
        let req = try request(path: "threads", accessToken: accessToken, query: q)
        let res: ListResponse<XFThread> = try await send(req)
        return Paged(items: res.data ?? [], pagination: res.pagination)
    }

    func getThread(id: Int, accessToken: String? = nil) async throws -> XFThread {
        let req = try request(path: "threads/\(id)", accessToken: accessToken)
        let res: SingleResponse<XFThread> = try await send(req)
        return res.data
    }

    // MARK: - Posts
    func listPosts(threadID: Int, page: Int? = nil, accessToken: String? = nil) async throws -> Paged<XFPost> {
        var q: [URLQueryItem] = []
        if let page = page { q.append(URLQueryItem(name: "page", value: String(page))) }
        let req = try request(path: "threads/\(threadID)/posts", accessToken: accessToken, query: q)
        let res: ListResponse<XFPost> = try await send(req)
        return Paged(items: res.data ?? [], pagination: res.pagination)
    }

    // MARK: - Create Thread / Reply / Upload
    // Creates a new thread in a forum (node)
    // Typical XenForo params: node_id, title, message, prefix_id?, tags[]?
    func createThread(nodeID: Int,
                      title: String,
                      message: String,
                      prefixID: Int? = nil,
                      tags: [String] = [],
                      attachmentHash: String? = nil,
                      accessToken: String? = nil) async throws -> XFThread {
        var form: [String: String] = [
            "node_id": String(nodeID),
            "title": title,
            "message": message
        ]
        if let prefixID = prefixID { form["prefix_id"] = String(prefixID) }
        if let attachmentHash = attachmentHash { form["attachment_hash"] = attachmentHash }
        for (i, tag) in tags.enumerated() { form["tags[\(i)]"] = tag }
        let req = try request(path: "threads", method: .POST, accessToken: accessToken, formData: form)
        let res: SingleResponse<XFThread> = try await send(req)
        return res.data
    }

    // Posts a reply to an existing thread
    // Typical XenForo params: message, attachment_hash? (if using uploads)
    func replyToThread(threadID: Int,
                       message: String,
                       attachmentHash: String? = nil,
                       accessToken: String? = nil) async throws -> XFPost {
        var form: [String: String] = ["message": message]
        if let attachmentHash = attachmentHash { form["attachment_hash"] = attachmentHash }
        let req = try request(path: "threads/\(threadID)/posts", method: .POST, accessToken: accessToken, formData: form)
        let res: SingleResponse<XFPost> = try await send(req)
        return res.data
    }

    // Uploads media into a media category
    // Some XenForo setups accept URL-based media via form: title, media_url, description, category_id
    func uploadMedia(categoryID: Int,
                     title: String,
                     mediaURL: URL,
                     description: String? = nil,
                     accessToken: String? = nil) async throws -> XFMedia {
        var form: [String: String] = [
            "category_id": String(categoryID),
            "title": title,
            "media_url": mediaURL.absoluteString
        ]
        if let description = description { form["description"] = description }
        let req = try request(path: "media", method: .POST, accessToken: accessToken, formData: form)
        let res: SingleResponse<XFMedia> = try await send(req)
        return res.data
    }

    // MARK: - Attachments
    struct AttachmentInitResponse: Decodable { let attachment_hash: String }
    // Initialize an attachment context (if XenForo instance requires it)
    func initAttachment(context: String = "post", accessToken: String? = nil) async throws -> String {
        let req = try request(path: "attachments", method: .POST, accessToken: accessToken, formData: ["context": context])
        let res: AttachmentInitResponse = try await send(req)
        return res.attachment_hash
    }

    // Upload a file to an attachment hash (multipart/form-data)
    func uploadAttachment(data: Data, filename: String, attachmentHash: String, accessToken: String? = nil) async throws {
        var req = try request(path: "attachments", method: .POST, accessToken: accessToken)
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"attachment_hash\"\r\n\r\n")
        append("\(attachmentHash)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        struct UploadRes: Decodable { let success: Bool }
        _ = try await send(req, as: UploadRes.self)
    }

    // MARK: - Edit/Delete
    func editThread(threadID: Int, title: String? = nil, prefixID: Int? = nil, accessToken: String? = nil) async throws -> XFThread {
        var form: [String: String] = [:]
        if let title = title { form["title"] = title }
        if let prefixID = prefixID { form["prefix_id"] = String(prefixID) }
        let req = try request(path: "threads/\(threadID)", method: .POST, accessToken: accessToken, formData: form)
        let res: SingleResponse<XFThread> = try await send(req)
        return res.data
    }

    func deleteThread(threadID: Int, hard: Bool = false, reason: String? = nil, accessToken: String? = nil) async throws {
        var q: [URLQueryItem] = []
        if hard { q.append(URLQueryItem(name: "hard_delete", value: "1")) }
        if let reason = reason { q.append(URLQueryItem(name: "reason", value: reason)) }
        let req = try request(path: "threads/\(threadID)", method: .DELETE, accessToken: accessToken, query: q)
        struct Success: Decodable { let success: Bool }
        _ = try await send(req, as: Success.self)
    }

    func editPost(postID: Int, message: String, accessToken: String? = nil) async throws -> XFPost {
        let form = ["message": message]
        let req = try request(path: "posts/\(postID)", method: .POST, accessToken: accessToken, formData: form)
        let res: SingleResponse<XFPost> = try await send(req)
        return res.data
    }

    func deletePost(postID: Int, hard: Bool = false, reason: String? = nil, accessToken: String? = nil) async throws {
        var q: [URLQueryItem] = []
        if hard { q.append(URLQueryItem(name: "hard_delete", value: "1")) }
        if let reason = reason { q.append(URLQueryItem(name: "reason", value: reason)) }
        let req = try request(path: "posts/\(postID)", method: .DELETE, accessToken: accessToken, query: q)
        struct Success: Decodable { let success: Bool }
        _ = try await send(req, as: Success.self)
    }

    // MARK: - Watch / Unwatch
    func watchThread(threadID: Int, state: String = "watch_no_email", accessToken: String? = nil) async throws {
        let req = try request(path: "threads/\(threadID)/watch", method: .POST, accessToken: accessToken, formData: ["state": state])
        struct Success: Decodable { let success: Bool }
        _ = try await send(req, as: Success.self)
    }

    func unwatchThread(threadID: Int, accessToken: String? = nil) async throws {
        let req = try request(path: "threads/\(threadID)/watch", method: .DELETE, accessToken: accessToken)
        struct Success: Decodable { let success: Bool }
        _ = try await send(req, as: Success.self)
    }

    // MARK: - Reactions
    func reactToPost(postID: Int, reactionID: Int, accessToken: String? = nil) async throws {
        let req = try request(path: "posts/\(postID)/reactions", method: .POST, accessToken: accessToken, formData: ["reaction_id": String(reactionID)])
        struct Success: Decodable { let success: Bool }
        _ = try await send(req, as: Success.self)
    }

    func removeReactionFromPost(postID: Int, accessToken: String? = nil) async throws {
        let req = try request(path: "posts/\(postID)/reactions", method: .DELETE, accessToken: accessToken)
        struct Success: Decodable { let success: Bool }
        _ = try await send(req, as: Success.self)
    }

    // MARK: - Search
    struct SearchCreateResponse: Decodable { let search_id: Int }
    func searchCreate(query: String, accessToken: String? = nil) async throws -> Int {
        let form = ["q": query]
        let req = try request(path: "search", method: .POST, accessToken: accessToken, formData: form)
        let res: SearchCreateResponse = try await send(req)
        return res.search_id
    }

    func searchResults(id: Int, accessToken: String? = nil) async throws -> (results: SearchResults, pagination: Pagination?) {
        let req = try request(path: "search/\(id)", accessToken: accessToken)
        let results = try await send(req, as: SearchResults.self)
        return (results, results.pagination)
    }

    func search(query: String, accessToken: String?) async throws -> SearchResults {
        let id = try await searchCreate(query: query, accessToken: accessToken)
        let tuple = try await searchResults(id: id, accessToken: accessToken)
        return tuple.results
    }
}

// MARK: - Models

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

    enum CodingKeys: String, CodingKey {
        case id = "resource_id"
        case title
        case iconURL = "icon_url"
        case coverURL = "cover_url"
        case fileSize = "file_size"
        case category = "category"
        case rating
        case ratingCount = "rating_count"
        case releaseDate = "release_date"
        case updatedDate = "update_date"
        case downloadCount = "download_count"
        case viewCount = "view_count"
        case tagLine = "tag_line"
    }
}

struct XFThread: Identifiable, Codable, Hashable {
    var id: Int
    var title: String
    var author: String
    var replyCount: Int
    var viewCount: Int
    var nodeID: Int?
    var userID: Int?
    var postDate: Date?

    enum CodingKeys: String, CodingKey {
        case id = "thread_id"
        case title
        case author = "username"
        case replyCount = "reply_count"
        case viewCount = "view_count"
        case nodeID = "node_id"
        case userID = "user_id"
        case postDate = "post_date"
    }
}

struct XFMedia: Identifiable, Codable, Hashable {
    var id: Int
    var title: String
    var mediaURL: URL
    var thumbnailURL: URL?

    enum CodingKeys: String, CodingKey {
        case id = "media_id"
        case title
        case mediaURL = "media_url"
        case thumbnailURL = "thumbnail_url"
    }
}

struct XFUser: Identifiable, Codable, Hashable {
    var id: Int
    var username: String
    var avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case username
        case avatarURL = "avatar_urls"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        // avatar_urls is a dictionary of sizes -> URL. Prefer the largest.
        if let dict = try? c.decode([String: URL].self, forKey: .avatarURL) {
            avatarURL = dict.values.sorted { $0.absoluteString > $1.absoluteString }.first
        } else {
            avatarURL = nil
        }
    }
}

struct XFNode: Identifiable, Codable, Hashable {
    var id: Int
    var title: String
    var nodeName: String?
    var description: String?
    var nodeTypeID: String
    var parentNodeID: Int?
    var displayOrder: Int?
    var displayInList: Bool?
    var viewURL: URL?
    var breadcrumbs: [Breadcrumb]?
    var typeData: [String: XFJSONValue]?

    struct Breadcrumb: Codable, Hashable { let node_id: Int; let title: String; let node_type_id: String }

    enum CodingKeys: String, CodingKey {
        case id = "node_id"
        case title
        case nodeName = "node_name"
        case description
        case nodeTypeID = "node_type_id"
        case parentNodeID = "parent_node_id"
        case displayOrder = "display_order"
        case displayInList = "display_in_list"
        case viewURL = "view_url"
        case breadcrumbs
        case typeData = "type_data"
    }
}

struct XFForum: Codable, Hashable { let forum_type_id: String?; let allow_posting: Bool?; let require_prefix: Bool?; let min_tags: Int? }
struct XFLinkForum: Codable, Hashable { let link_url: URL?; let redirect_count: Int? }
struct XFPage: Codable, Hashable { let publish_date: Int?; let view_count: Int? }

struct XFPoll: Identifiable, Codable, Hashable {
    var id: Int
    var question: String
    var voter_count: Int
    var can_vote: Bool?
    var has_voted: Bool?
    var public_votes: Bool?
    var max_votes: Int?
    var close_date: Int?
    var change_vote: Bool?
    var view_results_unvoted: Bool?
    var responses: [PollResponse]?
    struct PollResponse: Codable, Hashable { let response: String; let vote_count: Int?; let is_voted: Bool? }
    enum CodingKeys: String, CodingKey { case id = "poll_id", question, voter_count, can_vote, has_voted, public_votes, max_votes, close_date, change_vote, view_results_unvoted, responses }
}

struct XFPost: Identifiable, Codable, Hashable {
    var id: Int
    var thread_id: Int
    var user_id: Int
    var username: String
    var post_date: Int
    var message: String
    var message_parsed: String?
    var is_first_post: Bool?
    var is_last_post: Bool?
    var is_unread: Bool?
    var can_edit: Bool?
    var can_soft_delete: Bool?
    var can_hard_delete: Bool?
    var can_react: Bool?
    var can_view_attachments: Bool?
    var view_url: URL?
    var is_reacted_to: Bool?
    var visitor_reaction_id: Int?
    var vote_score: Int?
    var can_content_vote: Bool?
    var allowed_content_vote_types: [String]?
    var is_content_voted: Bool?
    var visitor_content_vote: String?
    var attach_count: Int?
    var warning_message: String?
    var position: Int?
    var last_edit_date: Int?
    var reaction_score: Int?

    enum CodingKeys: String, CodingKey {
        case id = "post_id", thread_id, user_id, username, post_date, message, message_parsed, is_first_post, is_last_post, is_unread, can_edit, can_soft_delete, can_hard_delete, can_react, can_view_attachments, view_url, is_reacted_to, visitor_reaction_id, vote_score, can_content_vote, allowed_content_vote_types, is_content_voted, visitor_content_vote, attach_count, warning_message, position, last_edit_date, reaction_score
    }
}

struct XFThreadField: Codable, Hashable { let field_id: String; let title: String; let description: String?; let display_order: Int?; let field_type: String?; let field_choices: [String: String]?; let match_type: String?; let match_params: [String]?; let max_length: Int?; let required: Bool?; let display_group: String? }

struct XFThreadPrefix: Codable, Hashable { let prefix_id: Int; let title: String; let description: String?; let usage_help: String?; let is_usable: Bool?; let prefix_group_id: Int?; let display_order: Int?; let materialized_order: Int? }

struct SearchResults: Decodable {
    var resources: [XFResource]
    var threads: [XFThread]
    var media: [XFMedia]
    var users: [XFUser]
    var pagination: XenForoAPI.Pagination?
}

// Generic JSON value for type_data
enum XFJSONValue: Codable, Hashable {
    case string(String), int(Int), double(Double), bool(Bool), array([XFJSONValue]), object([String: XFJSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: XFJSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([XFJSONValue].self) { self = .array(v); return }
        throw DecodingError.typeMismatch(XFJSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

// Helper to encode arbitrary Encodable into JSON body
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self._encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

