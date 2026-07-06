import Combine
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
    let itemID: Int
    var title: String
    var subtitle: String?
    var imageURL: URL?
    var linkURL: URL?
    var savedDate: Date

    var id: String { "\(kind.rawValue)-\(itemID)" }
}

final class SavedItemsStore: ObservableObject {
    static let shared = SavedItemsStore()

    @Published private(set) var items: [SavedItem] = [] {
        didSet { save() }
    }

    private let defaultsKey = "SavedItemsStore.items.v1"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? decoder.decode([SavedItem].self, from: data) {
            items = decoded.sorted { $0.savedDate > $1.savedDate }
        }
    }

    func items(kind: SavedItemKind? = nil) -> [SavedItem] {
        let filtered = kind.map { selectedKind in
            items.filter { $0.kind == selectedKind }
        } ?? items
        return filtered.sorted { $0.savedDate > $1.savedDate }
    }

    func isSaved(kind: SavedItemKind, id: Int) -> Bool {
        items.contains { $0.kind == kind && $0.itemID == id }
    }

    func toggle(resource: XFResource) {
        toggle(
            SavedItem(
                kind: .resource,
                itemID: resource.id,
                title: resource.title,
                subtitle: resource.category ?? resource.authorName ?? resource.tagLine,
                imageURL: resource.iconURL ?? resource.coverURL,
                linkURL: resource.viewURL,
                savedDate: Date()
            )
        )
    }

    func toggle(media: XFMedia) {
        toggle(
            SavedItem(
                kind: .media,
                itemID: media.id,
                title: media.title,
                subtitle: media.username ?? media.categoryTitle ?? media.kind.title,
                imageURL: media.thumbnailURL,
                linkURL: media.viewURL ?? media.mediaURL,
                savedDate: Date()
            )
        )
    }

    func toggle(thread: XFThread) {
        toggle(
            SavedItem(
                kind: .thread,
                itemID: thread.id,
                title: thread.title,
                subtitle: "Started by \(thread.author)",
                imageURL: nil,
                linkURL: nil,
                savedDate: Date()
            )
        )
    }

    func remove(_ item: SavedItem) {
        items.removeAll { $0.id == item.id }
    }

    func removeAll() {
        items.removeAll()
    }

    private func toggle(_ item: SavedItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
        } else {
            items.insert(item, at: 0)
        }
    }

    private func save() {
        guard let data = try? encoder.encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
