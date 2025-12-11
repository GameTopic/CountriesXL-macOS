import Foundation

// This was originally a standalone Swift script (with a shebang). To avoid
// compiler errors when the file is included in the app target, we keep the
// logic inside a function so there are no top-level statements.
//
// To run as a script outside Xcode, copy the function body into a separate
// Swift file or call `ensureLocalizations()` from a small `main.swift`.

func ensureLocalizations() {
    let fileManager = FileManager.default
    let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let basePath = repoRoot.appendingPathComponent("CountriesXL")

    let locales = ["en-GB", "es", "fr", "de"]

    let requiredKeys: [String: String] = [
        // Additional keys used by SettingsView and MoveToApplications that may be missing in some locales.
        "general.default": "Default",
        "file.choose": "Choose…",
        "general.demoOnly": "Demo only: No real directory change.",
        "general.resetWarning": "Restores all preferences to their factory values. This action can’t be undone.",
        "updates.help": "Manage update preferences including channels and automatic behavior.",
        "privacy.sendAnonymousUsageData": "Send Anonymous Usage Data",
        "privacy.clearCache": "Clear Cache/Data",
        "privacy.clearCacheInfo": "Removes temporary files and cached data. You may be signed out of services.",
        "privacy.appPermissions": "App Permissions",
        "privacy.notifications": "Notifications",
        "privacy.filesAccess": "Files Access",
        "privacy.locationAccess": "Location Access"
    ]

    for locale in locales {
        let dir = basePath.appendingPathComponent("\(locale).lproj")
        let file = dir.appendingPathComponent("Localizable.strings")

        guard fileManager.fileExists(atPath: file.path) else {
            print("[WARN] file missing for locale \(locale): \(file.path)")
            continue
        }

        guard var content = try? String(contentsOf: file, encoding: .utf8) else {
            print("[WARN] could not read file for locale \(locale)")
            continue
        }

        var appended = 0
        for (key, enValue) in requiredKeys {
            if content.contains("\"\(key)\"") { continue }
            // For non-en locales we'll keep the English fallback value but prefix with a locale marker to make it easy to replace.
            let value = "\(enValue)"
            content += "\n\"\(key)\" = \"\(value)\";\n"
            appended += 1
        }

        if appended > 0 {
            do {
                try content.write(to: file, atomically: true, encoding: .utf8)
                print("[OK] Appended \(appended) keys to \(locale)")
            } catch {
                print("[ERR] Failed to write file for locale \(locale): \(error)")
            }
        } else {
            print("[OK] No changes needed for \(locale)")
        }
    }

    print("Done. Review the locale files and adjust translations as needed.")
}

// No top-level execution to avoid compilation issues when included in the app target.
// To run manually in a script context, create a small launcher that calls `ensureLocalizations()`.
