import Foundation
import Combine

// MARK: - Strongly-Typed Settings Enums

enum AppColorScheme: String, Codable, CaseIterable, Equatable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
}

enum AppAccentColor: String, Codable, CaseIterable, Equatable {
    case blue = "Blue"
    case red = "Red"
    case green = "Green"
    case orange = "Orange"
    case purple = "Purple"
    case pink = "Pink"
    case yellow = "Yellow"
}

enum AppFontSize: String, Codable, CaseIterable, Equatable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
}

enum AppNotificationSound: String, Codable, CaseIterable, Equatable {
    case none = "None"
    case `default` = "Default"
    case custom = "Custom"
}

/// Error type specific to this file's settings operations
enum AppSettingsError: Error {
    case failedToLoad
    case failedToSave
}

struct TypedSettingsDraft: Codable, Equatable {
    var colorSchemeSelection: AppColorScheme = .system
    var accentColorSelection: AppAccentColor = .blue
    var fontSizeSelection: AppFontSize = .medium
    var notificationSound: AppNotificationSound = .default
    var isDarkModeEnabled: Bool = false
    var isNotificationsEnabled: Bool = true
}
