import SwiftUI
import Combine
import AuthenticationServices
import CoreLocation

@MainActor
final class AppState: ObservableObject {
    private let auth = AuthManager.shared
    private let settingsService = SettingsService.shared

    // Auth
    @Published var isAuthenticated: Bool = false
    @Published var accessToken: String? = nil
    @Published var userAvatarImage: Image? = nil

    // UI state
    @Published var showAlerts: Bool = false
    @Published var showMessages: Bool = false
    @Published var showSettings: Bool = false

    // Search
    @Published var searchQuery: String = ""

    // Settings model (lightweight, can be persisted later)
    @Published var settings: SettingsModel = SettingsService.shared.settings
    
    // Location info
    @Published var location: CLLocation? = nil
    @Published var locationDescription: String = ""

    private let api = XenForoAPI()
    
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Bridge SettingsStore.applied -> SettingsModel
    private func syncFromSettingsStoreApplied() {
        // Load persisted SettingsDraft from SettingsStore if present
        guard let data = UserDefaults.standard.data(forKey: "SettingsStore.applied"),
              let draft = try? JSONDecoder().decode(SettingsDraft.self, from: data) else { return }
        let mapped = mapSettings(from: draft)
        // To avoid "Publishing changes from within view updates" warnings, defer the assignment
        Task { @MainActor in
            if self.settingsService.settings != mapped {
                self.settingsService.settings = mapped
            }
        }
    }

    private func mapSettings(from draft: SettingsDraft) -> SettingsModel {
        var model = SettingsModel()
        // General
        model.startAtLogin = draft.startAtLogin
        model.languageCode = draft.languageRegion
        // Appearance
        switch draft.colorSchemeSelection {
        case .light: model.theme = .light
        case .dark: model.theme = .dark
        case .system: model.theme = .system
        }
        switch draft.accentColorSelection {
        case .blue: model.accentColor = CodableColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        case .red: model.accentColor = CodableColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
        case .green: model.accentColor = CodableColor(red: 0.298, green: 0.851, blue: 0.392, alpha: 1.0)
        case .orange: model.accentColor = CodableColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
        case .purple: model.accentColor = CodableColor(red: 0.686, green: 0.321, blue: 0.871, alpha: 1.0)
        case .pink: model.accentColor = CodableColor(red: 1.0, green: 0.176, blue: 0.333, alpha: 1.0)
        case .yellow: model.accentColor = CodableColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        }
        switch draft.fontSizeSelection {
            case .small: model.fontSize = .small
            case .medium: model.fontSize = .medium
            case .large: model.fontSize = .large
        }
        // Convert 0...100 slider to 0.0...1.0 transparency if needed
        model.windowTransparency = max(0.0, min(1.0, draft.windowTransparency / 100.0))
        // Privacy & Security
        model.sendAnonymousUsageData = draft.sendAnonymousUsageData
        model.adsDisabled = draft.adsDisabled
        model.videoAdsDisabled = draft.disableVideoAds
        // Account
        model.displayName = draft.displayName
        // Advanced
        model.developerMode = draft.developerModeEnabled
        if !draft.proxyConfiguration.isEmpty {
            let parts = draft.proxyConfiguration.split(separator: ":")
            if parts.count == 2 {
                model.proxyHost = String(parts[0])
                model.proxyPort = Int(parts[1]) ?? 0
            }
        }
        // Notifications
        model.notificationSounds = draft.notificationSound != .none
        model.badgeAppIcon = draft.badgeAppIcon
        // Experimental
        model.enableBetaFeatures = draft.betaFeaturesEnabled
        return model
    }

    init() {
        auth.configure(clientID: "1316758746340916", clientSecret: "3fy1zCUu9_KE7k6-3sKi2JFLqfObyDJ_", redirectURI: "https://tyleraustins.com/connected_account.php", authURL: URL(string: "https://cities-mods.com/oauth2/authorize")!, tokenURL: URL(string: "https://cities-mods.com/api/oauth2/token")!, revokeURL: URL(string: "https://cities-mods.com/api/oauth2/revoke")!)
        auth.restoreFromKeychain()
        self.isAuthenticated = auth.isAuthenticated
        self.accessToken = auth.accessToken
        
        self.location = LocationService.shared.location
        self.locationDescription = LocationService.shared.placemarkDescription

        LocationService.shared.$location
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                self?.location = loc
            }
            .store(in: &cancellables)

        LocationService.shared.$placemarkDescription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] desc in
                self?.locationDescription = desc
            }
            .store(in: &cancellables)

        // Bridge persisted SettingsStore values into our SettingsModel
        syncFromSettingsStoreApplied()
        // Observe UserDefaults changes to re-sync when SettingsStore.apply() updates persistence
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.syncFromSettingsStoreApplied()
            }
            .store(in: &cancellables)
        
        // Sync settings from single source of truth
        settingsService.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                guard let self else { return }
                if self.settings != newSettings {
                    self.settings = newSettings
                }
            }
            .store(in: &cancellables)

        // When AppState.settings changes (e.g., UI writes), push to service
        $settings
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newValue in
                guard let self else { return }
                if self.settingsService.settings != newValue {
                    self.settingsService.settings = newValue
                }
            }
            .store(in: &cancellables)
    }

    func beginSignInFlow() async {
        await auth.signIn()
        self.isAuthenticated = auth.isAuthenticated
        self.accessToken = auth.accessToken
        await loadCurrentUserAvatar()
    }

    func signOut() async {
        await auth.revokeTokenIfPossible()
        auth.signOut()
        accessToken = nil
        isAuthenticated = false
        userAvatarImage = nil
    }

    func loadCurrentUserAvatar() async {
        guard let token = accessToken else { return }
        do {
            let avatarURL = try await api.currentUserAvatarURL(accessToken: token)
            if let image = try? await loadImage(from: avatarURL) {
                userAvatarImage = Image(nsImage: image)
            }
        } catch {
            // handle error silently for now
        }
    }

    private func loadImage(from url: URL) async throws -> NSImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        return image
    }
}

// MARK: - Settings Model

struct SettingsModel: Codable, Equatable {
    // General
    var startAtLogin: Bool = false
    var languageCode: String = Locale.current.identifier

    // Appearance
    enum Theme: String, CaseIterable, Codable { case system, light, dark }
    var theme: Theme = .system
    var accentColor: CodableColor? = nil // nil => use system accent
    enum FontSize: String, CaseIterable, Codable { case small, medium, large }
    var fontSize: FontSize = .medium
    var windowTransparency: Double = 0.0 // 0..1

    // Privacy & Security
    var biometricLock: Bool = false
    var sendAnonymousUsageData: Bool = false
    var adsDisabled: Bool = true // No ads as requested
    var videoAdsDisabled: Bool = true

    // Account
    var displayName: String = ""

    // Advanced
    var developerMode: Bool = false
    var proxyHost: String = ""
    var proxyPort: Int = 0

    // Notifications
    var notificationSounds: Bool = true
    var badgeAppIcon: Bool = true

    // Experimental
    var enableBetaFeatures: Bool = false

    // Convenience gates
    var areAdsAllowed: Bool { !adsDisabled }
    var areVideoAdsAllowed: Bool { !adsDisabled && !videoAdsDisabled }
}

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

