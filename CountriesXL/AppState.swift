import Foundation
import Combine
import SwiftUI
import ServiceManagement
import AppKit

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

    init() {
        // Authentication and user session defaults
        self.accessToken = nil
        self.isAuthenticated = false
        self.showSettings = false
        self.searchQuery = ""
        self.userAvatarImage = nil
        self.settings = SettingsService.shared.settings

        // Restore persisted media options
        if let sort = MediaSortOption(rawValue: mediaSortRaw) { self.mediaSort = sort }
        if let filter = MediaFilterOption(rawValue: mediaFilterRaw) { self.mediaFilter = filter }
    }

    // Begin sign-in flow placeholder
    func beginSignInFlow() async {
        // Implement real sign-in; for now, toggle flag
        isAuthenticated = true
    }

    func signOut() async {
        accessToken = nil
        isAuthenticated = false
        userAvatarImage = nil
    }
}

enum AppSettings {
    enum Error: LocalizedError {
        case invalidProxyFormat
        case downloadFolderMissing(path: String)
        case downloadFolderNotDirectory(path: String)
        case customDirMissing(path: String)
        case customDirNotDirectory(path: String)
        case startAtLoginFailure(message: String)

        var errorDescription: String? {
            switch self {
            case .invalidProxyFormat:
                return "Proxy must be in the form host:port."
            case .downloadFolderMissing(let path):
                return "The selected download folder does not exist: \(path)"
            case .downloadFolderNotDirectory(let path):
                return "The selected download path is not a folder: \(path)"
            case .customDirMissing(let path):
                return "The custom data directory does not exist: \(path)"
            case .customDirNotDirectory(let path):
                return "The custom data directory path is not a folder: \(path)"
            case .startAtLoginFailure(let message):
                return "Failed to update Start at Login: \(message)"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .invalidProxyFormat:
                return "Use a hostname or IP address followed by a colon and a port number, e.g., proxy.example.com:8080."
            case .downloadFolderMissing:
                return "Choose a different folder or allow the app to create it for you."
            case .downloadFolderNotDirectory:
                return "Select a directory (folder), not a file."
            case .customDirMissing:
                return "Choose a different directory or allow the app to create it for you."
            case .customDirNotDirectory:
                return "Select a directory (folder), not a file."
            case .startAtLoginFailure:
                return "Open System Settings > General > Login Items and ensure the helper is allowed, or try again."
            }
        }
    }

    struct SettingsDraft: Codable, Equatable {
        // General
        var videoAutoplayEnabled: Bool = true
        var startAtLogin: Bool = false
        var languageRegion: String = "English (US / CA)"
        var downloadPath: String = "" // Human-readable path for UI
        // Presentation preference: choose whether help dialogs open as separate windows
        var preferDialogsAsSeparateWindows: Bool = false
        // Whether the user has completed/seen the Tour
        var hasSeenTour: Bool = false

        // Privacy
        var pushNotificationsEnabled: Bool = true
        var sendAnonymousUsageData: Bool = true
        var locationEnabled: Bool = true
        var adsDisabled: Bool = true
        var disableVideoAds: Bool = true

        // Appearance
        var colorSchemeSelection: AppColorScheme = .system
        var accentColorSelection: AppAccentColor = .blue
        var fontSizeSelection: AppFontSize = .medium
        var windowTransparency: Double = 0 // 0...100

        // Notifications
        var notificationSound: AppNotificationSound = .default // None, Default, Custom
        var badgeAppIcon: Bool = true

        // Account
        var displayName: String = ""
        var twoFactorAuthEnabled: Bool = false

        // Advanced
        var customDataDirectory: String = ""
        var developerModeEnabled: Bool = false
        var proxyConfiguration: String = "" // host:port

        // Experimental
        var betaFeaturesEnabled: Bool = false
        var showIntegrationStatusInfo: Bool = false

        // Updates
        var updatesAutoChecks: Bool = false
        var updatesAutoDownloads: Bool = false
        var updatesCheckOnLaunch: Bool = false
        var updatesAutoInstall: Bool = false

        // New: Remote render endpoint (optional) and DRM playback option
        /// Optional server URL used to render XF BBCode on the server. If nil, local rendering is used or auto-discovered endpoints are tried.
        var remoteRenderEndpoint: String? = nil

        /// When true, the app will attempt DRM-aware playback flows where supported. Default is false.
        var drmPlaybackEnabled: Bool = true

        /// Optional DRM license server endpoint used for FairPlay license (CKC) requests.
        var drmLicenseEndpoint: String = ""
    }

    struct AppCodableColor: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        init(systemColor: NSColor) {
            self.red = Double(systemColor.redComponent)
            self.green = Double(systemColor.greenComponent)
            self.blue = Double(systemColor.blueComponent)
            self.alpha = Double(systemColor.alphaComponent)
        }

        var nsColor: NSColor {
            return NSColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
        }
    }

    @MainActor
    final class SettingsStore: ObservableObject {
        private func mapToSettingsModel(from draft: SettingsDraft) -> SettingsModel {
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
            case .blue:
                model.accentColor = CodableColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
            case .red:
                model.accentColor = CodableColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
            case .green:
                model.accentColor = CodableColor(red: 0.298, green: 0.851, blue: 0.392, alpha: 1.0)
            case .orange:
                model.accentColor = CodableColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
            case .purple:
                model.accentColor = CodableColor(red: 0.686, green: 0.321, blue: 0.871, alpha: 1.0)
            case .pink:
                model.accentColor = CodableColor(red: 1.0, green: 0.176, blue: 0.333, alpha: 1.0)
            case .yellow:
                model.accentColor = CodableColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
            }
            switch draft.fontSizeSelection {
                case .small: model.fontSize = .small
                case .medium: model.fontSize = .medium
                case .large: model.fontSize = .large
            }
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
            // Presentation preference
            model.preferDialogsAsSeparateWindows = draft.preferDialogsAsSeparateWindows
            model.hasSeenTour = draft.hasSeenTour
            // New fields
            model.remoteRenderEndpoint = (draft.remoteRenderEndpoint?.isEmpty == false) ? draft.remoteRenderEndpoint : nil
            model.drmPlaybackEnabled = draft.drmPlaybackEnabled
            return model
        }

        // The draft being edited by the UI
        @Published var draft: SettingsDraft

        // Persisted (applied) values
        private var applied: SettingsDraft

        // Download integration: keep a bookmark so we can access the folder in sandbox
        private var downloadBookmarkData: Data?

        // Persistence keys
        private let defaultsKey = "SettingsStore.applied"
        private let bookmarkKey = "SettingsStore.downloadBookmark"
        private let loginItemIdentifier: String? = Bundle.main.object(forInfoDictionaryKey: "LoginItemBundleIdentifier") as? String

        var directoryCreationPrompt: ((String) async -> Bool)? = nil

        init() {
            // Load persisted values if available
            if let data = UserDefaults.standard.data(forKey: defaultsKey),
               let decoded = try? JSONDecoder().decode(SettingsDraft.self, from: data) {
                self.applied = decoded
            } else {
                self.applied = SettingsDraft()
            }
            self.draft = applied

            // Load bookmark if present
            self.downloadBookmarkData = UserDefaults.standard.data(forKey: bookmarkKey)
            // If we have a bookmark but no visible path, try to resolve a path for UI
            if draft.downloadPath.isEmpty, let url = resolveDownloadURL() {
                self.draft.downloadPath = url.path
            }
        }

        // Apply changes: validate, persist, and refresh applied state
        func apply() async throws {
            // Example validation: if proxy is set, ensure basic format host:port
            if !draft.proxyConfiguration.isEmpty {
                let parts = draft.proxyConfiguration.split(separator: ":")
                if parts.count != 2 || Int(parts[1]) == nil {
                    throw AppSettings.Error.invalidProxyFormat
                }
            }

            // Validate or create download path
            if !draft.downloadPath.isEmpty {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: draft.downloadPath, isDirectory: &isDir)
                if !exists {
                    // Ask to create (non-blocking by default). If no prompt, attempt auto-create.
                    let shouldCreate = try await withCheckedThrowingContinuation { continuation in
                        Task { @MainActor in
                            if let prompt = directoryCreationPrompt {
                                let result = await prompt(draft.downloadPath)
                                continuation.resume(returning: result)
                            } else {
                                continuation.resume(returning: true)
                            }
                        }
                    }
                    if shouldCreate {
                        do {
                            try FileManager.default.createDirectory(atPath: draft.downloadPath, withIntermediateDirectories: true)
                        } catch {
                            throw AppSettings.Error.downloadFolderMissing(path: draft.downloadPath)
                        }
                    } else {
                        throw AppSettings.Error.downloadFolderMissing(path: draft.downloadPath)
                    }
                }
                var isDir2: ObjCBool = false
                guard FileManager.default.fileExists(atPath: draft.downloadPath, isDirectory: &isDir2), isDir2.boolValue else {
                    throw AppSettings.Error.downloadFolderNotDirectory(path: draft.downloadPath)
                }
            }

            // Validate or create custom data directory
            if !draft.customDataDirectory.isEmpty {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: draft.customDataDirectory, isDirectory: &isDir)
                if !exists {
                    let shouldCreate = try await withCheckedThrowingContinuation { continuation in
                        Task { @MainActor in
                            if let prompt = directoryCreationPrompt {
                                let result = await prompt(draft.customDataDirectory)
                                continuation.resume(returning: result)
                            } else {
                                continuation.resume(returning: true)
                            }
                        }
                    }
                    if shouldCreate {
                        do {
                            try FileManager.default.createDirectory(atPath: draft.customDataDirectory, withIntermediateDirectories: true)
                        } catch {
                            throw AppSettings.Error.customDirMissing(path: draft.customDataDirectory)
                        }
                    } else {
                        throw AppSettings.Error.customDirMissing(path: draft.customDataDirectory)
                    }
                }
                var isDir2: ObjCBool = false
                guard FileManager.default.fileExists(atPath: draft.customDataDirectory, isDirectory: &isDir2), isDir2.boolValue else {
                    throw AppSettings.Error.customDirNotDirectory(path: draft.customDataDirectory)
                }
            }

            // Handle download integration: create/update bookmark for the chosen folder
            if !draft.downloadPath.isEmpty {
                let url = URL(fileURLWithPath: draft.downloadPath, isDirectory: true)
                do {
                    let bookmark = try url.bookmarkData(options: URL.BookmarkCreationOptions.withSecurityScope, includingResourceValuesForKeys: nil as Set<URLResourceKey>?, relativeTo: nil)
                    self.downloadBookmarkData = bookmark
                    UserDefaults.standard.set(bookmark, forKey: bookmarkKey)

                    // Resolve bookmark to normalize the display path for UI
                    var stale = false
                    if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                        self.draft.downloadPath = resolved.path
                    }
                } catch {
                    // Non-fatal: still allow applying other settings
                    print("Warning: Failed to create download folder bookmark: \(error)")
                }
            } else {
                self.downloadBookmarkData = nil
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
            }

            // Configure Start at Login via ServiceManagement (requires a login item helper target)
            do {
                try configureStartAtLogin(enabled: draft.startAtLogin)
            } catch {
                // Surface the error to the caller so the alert shows meaningful info
                throw AppSettings.Error.startAtLoginFailure(message: error.localizedDescription)
            }

            // Ensure consistency: if all ads are disabled, video ads must also be disabled
            if draft.adsDisabled {
                draft.disableVideoAds = true
            }

            // Persist applied settings
            let data = try JSONEncoder().encode(draft)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            UserDefaults.standard.set(draft.locationEnabled, forKey: "LocationEnabled")

            // Synchronize Sparkle update preferences and persist convenience flags
            #if os(macOS)
            SparkleUpdater.shared.automaticallyChecksForUpdates = draft.updatesAutoChecks
            SparkleUpdater.shared.automaticallyDownloadsUpdates = draft.updatesAutoDownloads
            #endif
            UserDefaults.standard.set(draft.updatesAutoChecks, forKey: "updatesAutoChecks")
            UserDefaults.standard.set(draft.updatesAutoDownloads, forKey: "updatesAutoDownloads")
            UserDefaults.standard.set(draft.updatesCheckOnLaunch, forKey: "updatesCheckOnLaunch")
            UserDefaults.standard.set(draft.updatesAutoInstall, forKey: "updatesAutoInstall")

            // Simulate async work if needed
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms

            // Commit
            self.applied = draft

            // Update single source of truth service so the entire app reflects changes immediately
            let mappedModel = mapToSettingsModel(from: draft)
            Task { @MainActor in
                if !SettingsService.shared.settings.isSemanticallyEqual(to: mappedModel) {
                    SettingsService.shared.settings = mappedModel
                }
            }
        }

        // Cancel edits: revert draft back to last applied
        func cancel() {
            self.draft = applied
        }

        // Reset to defaults: reset draft (does not immediately persist until apply)
        func resetToDefaults() {
            self.draft = SettingsDraft()
        }

        // MARK: - Download Helpers

        // Resolve the download URL from bookmark or path
        func resolveDownloadURL() -> URL? {
            // Prefer bookmark if available
            if let bookmark = downloadBookmarkData {
                var isStale = false
                do {
                    let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
                    return url
                } catch {
                    print("Warning: Failed to resolve bookmark: \(error)")
                }
            }
            // Fallback to plain path
            guard !applied.downloadPath.isEmpty else { return nil }
            return URL(fileURLWithPath: applied.downloadPath, isDirectory: true)
        }

        // Call before performing downloads to access the folder in sandbox
        func beginAccessingDownloadFolder() -> URL? {
            guard let url = resolveDownloadURL() else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return url
        }

        // Call when download operations complete
        func endAccessingDownloadFolder(_ url: URL?) {
            url?.stopAccessingSecurityScopedResource()
        }

        // Clear the saved security-scoped bookmark for the download folder.
        // Optionally reset the visible path as well.
        func clearDownloadBookmark(resetPath: Bool = false) {
            self.downloadBookmarkData = nil
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            if resetPath {
                self.draft.downloadPath = ""
                self.applied.downloadPath = ""
            }
        }

        // MARK: - Start at Login
        private func configureStartAtLogin(enabled: Bool) throws {
            // This requires a separate Login Item helper app in your project.
            // Provide its bundle identifier in Info.plist under key `LoginItemBundleIdentifier`.
            guard let identifier = loginItemIdentifier else {
                // If no identifier is configured, treat as a no-op.
                return
            }
            let service = SMAppService.loginItem(identifier: identifier)
            if enabled {
                do {
                    try service.register()
                } catch {
                    throw error
                }
            } else {
                do {
                    try service.unregister()
                } catch {
                    throw error
                }
            }
        }

        // MARK: - Diagnostics
        func loginItemStatusString() -> String {
            guard let identifier = loginItemIdentifier else { return "Not configured" }
            let service = SMAppService.loginItem(identifier: identifier)
            if #available(macOS 13.0, *) {
                switch service.status {
                case .enabled:
                    return "Enabled"
                case .requiresApproval:
                    return "Requires Approval"
                case .notRegistered:
                    return "Not Registered"
                case .notFound:
                    return "Not Found"
                @unknown default:
                    return "Unknown"
                }
            } else {
                return "Unknown (requires macOS 13+)"
            }
        }

        func setLoginItemEnabled(_ enabled: Bool) throws {
            try configureStartAtLogin(enabled: enabled)
        }
    }
} // <-- Insert closing brace here to close enum AppSettings


extension SettingsModel {
    // Fallback semantic comparison to avoid relying on Equatable conformance here
    func isSemanticallyEqual(to other: SettingsModel) -> Bool {
        return self.startAtLogin == other.startAtLogin &&
               self.languageCode == other.languageCode &&
               self.theme == other.theme &&
               self.accentColor == other.accentColor &&
               self.fontSize == other.fontSize &&
               self.windowTransparency == other.windowTransparency &&
               self.sendAnonymousUsageData == other.sendAnonymousUsageData &&
               self.adsDisabled == other.adsDisabled &&
               self.videoAdsDisabled == other.videoAdsDisabled &&
               self.displayName == other.displayName &&
               self.developerMode == other.developerMode &&
               self.proxyHost == other.proxyHost &&
               self.proxyPort == other.proxyPort &&
               self.notificationSounds == other.notificationSounds &&
               self.badgeAppIcon == other.badgeAppIcon &&
               self.enableBetaFeatures == other.enableBetaFeatures &&
               self.preferDialogsAsSeparateWindows == other.preferDialogsAsSeparateWindows &&
               self.hasSeenTour == other.hasSeenTour &&
               self.remoteRenderEndpoint == other.remoteRenderEndpoint &&
               self.drmPlaybackEnabled == other.drmPlaybackEnabled
    }
}
