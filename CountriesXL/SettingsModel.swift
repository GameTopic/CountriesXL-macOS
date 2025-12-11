import Foundation
import SwiftUI

struct SettingsModel: Codable, Equatable {
    // General
    var startAtLogin: Bool = false
    var languageCode: String = Locale.current.identifier

    // Appearance
    enum Theme: String, CaseIterable, Codable { case system, light, dark }
    var theme: Theme = .system
    var accentColor: CodableColor? = nil

    enum FontSize: String, CaseIterable, Codable { case small, medium, large }
    var fontSize: FontSize = .medium

    // Window & UI
    var windowTransparency: Double = 0.0

    // Privacy & Account
    var sendAnonymousUsageData: Bool = true
    var adsDisabled: Bool = true
    var videoAdsDisabled: Bool = true
    var displayName: String = ""

    // Advanced
    var developerMode: Bool = false
    var proxyHost: String? = nil
    var proxyPort: Int = 0

    // Notifications
    var notificationSounds: Bool = true
    var badgeAppIcon: Bool = true

    // Experimental
    var enableBetaFeatures: Bool = false

    // Presentation
    var preferDialogsAsSeparateWindows: Bool = false
    var hasSeenTour: Bool = false

    // New fields
    var remoteRenderEndpoint: String? = nil
    var drmPlaybackEnabled: Bool = true
    var drmLicenseEndpoint: String? = nil

    // Media preferences
    enum MediaQuality: String, CaseIterable, Codable { case auto, high, medium, low }
    var mediaQuality: MediaQuality = .auto
    var mediaAutoplayEnabled: Bool = true
    var mediaSubtitlesEnabled: Bool = true
}
