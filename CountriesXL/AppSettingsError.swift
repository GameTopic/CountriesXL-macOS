import Foundation
import Combine

// MARK: - Strongly-Typed Settings Enums

public enum AppColorScheme: String, Codable, CaseIterable, Equatable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
}

public enum AppAccentColor: String, Codable, CaseIterable, Equatable {
    case blue = "Blue"
    case red = "Red"
    case green = "Green"
    case orange = "Orange"
    case purple = "Purple"
    case pink = "Pink"
    case yellow = "Yellow"
}

public enum AppFontSize: String, Codable, CaseIterable, Equatable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
}

public enum AppNotificationSound: String, Codable, CaseIterable, Equatable {
    case none = "None"
    case `default` = "Default"
    case custom = "Custom"
}

/// Error type specific to this file's settings operations
public enum AppSettingsError: Error, LocalizedError {
    case failedToLoad
    case failedToSave
    
    public var errorDescription: String? {
        switch self {
        case .failedToLoad:
            return "Failed to load settings."
        case .failedToSave:
            return "Failed to save settings."
        }
    }
}

public struct TypedSettingsDraft: Codable, Equatable {
    var colorSchemeSelection: AppColorScheme = .system
    var accentColorSelection: AppAccentColor = .blue
    var fontSizeSelection: AppFontSize = .medium
    var notificationSound: AppNotificationSound = .default
    var isDarkModeEnabled: Bool = false
    var isNotificationsEnabled: Bool = true

    // Nearest-match helper for accent color from CodableColor
    private static func nearestAccent(from color: CodableColor?) -> AppAccentColor {
        guard let c = color else { return .blue }
        let candidates: [(AppAccentColor, (Double, Double, Double))] = [
            (.blue,   (0.0,   0.478, 1.0)),
            (.red,    (1.0,   0.231, 0.188)),
            (.green,  (0.298, 0.851, 0.392)),
            (.orange, (1.0,   0.584, 0.0)),
            (.purple, (0.686, 0.321, 0.871)),
            (.pink,   (1.0,   0.176, 0.333)),
            (.yellow, (1.0,   0.8,   0.0))
        ]
        let r = Double(c.red), g = Double(c.green), b = Double(c.blue)
        var best: (AppAccentColor, Double) = (.blue, Double.greatestFiniteMagnitude)
        for (name, (cr, cg, cb)) in candidates {
            let dr = r - cr, dg = g - cg, db = b - cb
            let dist = dr*dr + dg*dg + db*db
            if dist < best.1 { best = (name, dist) }
        }
        return best.0
    }
    
    private static func canonicalCodableColor(for accent: AppAccentColor) -> CodableColor {
        switch accent {
        case .blue:   return CodableColor(red: 0.0,   green: 0.478, blue: 1.0,   alpha: 1.0)
        case .red:    return CodableColor(red: 1.0,   green: 0.231, blue: 0.188, alpha: 1.0)
        case .green:  return CodableColor(red: 0.298, green: 0.851, blue: 0.392, alpha: 1.0)
        case .orange: return CodableColor(red: 1.0,   green: 0.584, blue: 0.0,   alpha: 1.0)
        case .purple: return CodableColor(red: 0.686, green: 0.321, blue: 0.871, alpha: 1.0)
        case .pink:   return CodableColor(red: 1.0,   green: 0.176, blue: 0.333, alpha: 1.0)
        case .yellow: return CodableColor(red: 1.0,   green: 0.8,   blue: 0.0,   alpha: 1.0)
        }
    }

    // MARK: - Bridging
    init(from settingsDraft: SettingsDraft) {
        self.colorSchemeSelection = settingsDraft.colorSchemeSelection
        self.accentColorSelection = settingsDraft.accentColorSelection
        self.fontSizeSelection = settingsDraft.fontSizeSelection
        self.notificationSound = settingsDraft.notificationSound
        // Derive dark mode flag from selection
        self.isDarkModeEnabled = settingsDraft.colorSchemeSelection == .dark
        self.isNotificationsEnabled = settingsDraft.badgeAppIcon && (settingsDraft.notificationSound != .none)
    }

    init(from settingsModel: SettingsModel) {
        // Map SettingsModel -> TypedSettingsDraft using best-effort defaults
        switch settingsModel.theme {
        case .dark: self.colorSchemeSelection = .dark
        case .light: self.colorSchemeSelection = .light
        case .system: self.colorSchemeSelection = .system
        }
        self.accentColorSelection = Self.nearestAccent(from: settingsModel.accentColor)
        switch settingsModel.fontSize {
        case .small: self.fontSizeSelection = .small
        case .medium: self.fontSizeSelection = .medium
        case .large: self.fontSizeSelection = .large
        }
        self.notificationSound = settingsModel.notificationSounds ? .default : .none
        self.isDarkModeEnabled = (settingsModel.theme == .dark)
        self.isNotificationsEnabled = settingsModel.badgeAppIcon && settingsModel.notificationSounds
    }

    func toSettingsDraft(_ base: SettingsDraft) -> SettingsDraft {
        var copy = base
        copy.colorSchemeSelection = self.colorSchemeSelection
        copy.accentColorSelection = self.accentColorSelection
        copy.fontSizeSelection = self.fontSizeSelection
        copy.notificationSound = self.notificationSound
        // badge icon as proxy for notifications enabled
        copy.badgeAppIcon = self.isNotificationsEnabled
        return copy
    }

    func toSettingsModel(_ base: SettingsModel) -> SettingsModel {
        var copy = base
        switch self.colorSchemeSelection {
        case .dark: copy.theme = .dark
        case .light: copy.theme = .light
        case .system: copy.theme = .system
        }
        switch self.fontSizeSelection {
        case .small: copy.fontSize = .small
        case .medium: copy.fontSize = .medium
        case .large: copy.fontSize = .large
        }
        copy.notificationSounds = (self.notificationSound != .none)
        copy.badgeAppIcon = self.isNotificationsEnabled
        copy.accentColor = Self.canonicalCodableColor(for: self.accentColorSelection)
        return copy
    }
}
