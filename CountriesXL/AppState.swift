import Foundation
import Combine
import SwiftUI

// MARK: - Media UI Options
enum MediaSortOption: String, CaseIterable, Identifiable {
    case dateDesc = "Newest first"
    case dateAsc = "Oldest first"
    case titleAZ = "Title A–Z"
    case titleZA = "Title Z–A"
    var id: String { rawValue }
}

enum MediaFilterOption: String, CaseIterable, Identifiable {
    case all = "All"
    case videos = "Videos"
    case images = "Images"
    var id: String { rawValue }
}

@MainActor
final class AppState: ObservableObject {
    // Authentication and user session
    @Published var accessToken: String? = nil
    @Published var isAuthenticated: Bool = false

    // UI state
    @Published var showSettings: Bool = false
    @Published var searchQuery: String = ""
    @Published private(set) var savedItems: [SavedItem] = []
    @Published private(set) var recentItems: [SavedItem] = []

    // Media view preferences controlled from the toolbar options menu
    @AppStorage("mediaSortOptionRaw") private var mediaSortRaw: String = MediaSortOption.dateDesc.rawValue
    @AppStorage("mediaFilterOptionRaw") private var mediaFilterRaw: String = MediaFilterOption.all.rawValue

    @Published var mediaSort: MediaSortOption = .dateDesc {
        didSet { mediaSortRaw = mediaSort.rawValue }
    }
    @Published var mediaFilter: MediaFilterOption = .all {
        didSet { mediaFilterRaw = mediaFilter.rawValue }
    }

    // User images (optional avatar image for toolbar)
    @Published var userAvatarImage: Image? = nil

    // Settings single source of truth bridged from SettingsStore
    @Published var settings: SettingsModel = SettingsService.shared.settings

    private var cancellables = Set<AnyCancellable>()

    init() {
        AuthManager.shared.restoreFromKeychain()

        self.accessToken = AuthManager.shared.accessToken
        self.isAuthenticated = AuthManager.shared.isAuthenticated
        self.showSettings = false
        self.searchQuery = ""
        self.savedItems = Self.loadSavedItems()
        self.recentItems = Self.loadRecentItems()
        self.userAvatarImage = nil
        self.settings = SettingsService.shared.settings

        // Restore persisted media options
        if let sort = MediaSortOption(rawValue: mediaSortRaw) { self.mediaSort = sort }
        if let filter = MediaFilterOption(rawValue: mediaFilterRaw) { self.mediaFilter = filter }

        AuthManager.shared.$accessToken
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                self?.accessToken = token
            }
            .store(in: &cancellables)

        AuthManager.shared.$isAuthenticated
            .receive(on: RunLoop.main)
            .sink { [weak self] isAuthenticated in
                self?.isAuthenticated = isAuthenticated
            }
            .store(in: &cancellables)

        SettingsService.shared.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                self?.settings = settings
            }
            .store(in: &cancellables)
    }

    func beginSignInFlow() async {
        await AuthManager.shared.signIn()
    }

    func signOut() async {
        await AuthManager.shared.revokeTokenIfPossible()
        AuthManager.shared.signOut()
        userAvatarImage = nil
    }

    func isSaved(_ item: SavedItem) -> Bool {
        savedItems.contains { $0.kind == item.kind && $0.sourceID == item.sourceID }
    }

    func toggleSaved(_ item: SavedItem) {
        if let index = savedItems.firstIndex(where: { $0.kind == item.kind && $0.sourceID == item.sourceID }) {
            savedItems.remove(at: index)
        } else {
            savedItems.insert(item, at: 0)
        }

        persistSavedItems()
    }

    func removeSavedItem(_ item: SavedItem) {
        savedItems.removeAll { $0.kind == item.kind && $0.sourceID == item.sourceID }
        persistSavedItems()
    }

    func recordRecentlyViewed(_ item: SavedItem) {
        var updatedItem = item
        updatedItem.savedAt = Date()
        recentItems.removeAll { $0.kind == item.kind && $0.sourceID == item.sourceID }
        recentItems.insert(updatedItem, at: 0)
        if recentItems.count > 30 {
            recentItems = Array(recentItems.prefix(30))
        }
        persistRecentItems()
    }

    func clearRecentItems() {
        recentItems.removeAll()
        persistRecentItems()
    }

    func removeRecentItem(_ item: SavedItem) {
        recentItems.removeAll { $0.kind == item.kind && $0.sourceID == item.sourceID }
        persistRecentItems()
    }

    private func persistSavedItems() {
        guard let data = try? JSONEncoder().encode(savedItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedItemsDefaultsKey)
    }

    private func persistRecentItems() {
        guard let data = try? JSONEncoder().encode(recentItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentItemsDefaultsKey)
    }

    private static func loadSavedItems() -> [SavedItem] {
        guard let data = UserDefaults.standard.data(forKey: savedItemsDefaultsKey),
              let items = try? JSONDecoder().decode([SavedItem].self, from: data) else {
            return []
        }

        return items
    }

    private static func loadRecentItems() -> [SavedItem] {
        guard let data = UserDefaults.standard.data(forKey: recentItemsDefaultsKey),
              let items = try? JSONDecoder().decode([SavedItem].self, from: data) else {
            return []
        }

        return items
    }

    private static let savedItemsDefaultsKey = "savedItems.v1"
    private static let recentItemsDefaultsKey = "recentItems.v1"
}
