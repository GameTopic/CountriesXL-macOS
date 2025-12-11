import Foundation

#if os(macOS)
import AppKit

/// Enhanced, self-contained implementation inspired by the "Let's Move" utility.
/// - Detects running from a mounted disk image (e.g., /Volumes/...)
/// - Detects running from a read-only volume (even if not under /Volumes)
/// - Prompts the user to move to /Applications (or ~/Applications if needed)
/// - Handles name conflicts by moving existing destination app to Trash
/// - Removes quarantine attributes on the copied app (best effort)
/// - Optional reveal in Finder after moving
/// - Relaunches the new copy and quits this instance after confirming the new instance started
/// - Localized strings via NSLocalizedString keys
///
/// For the original project (if/when available):
/// https://github.com/sparkle-project/lets-move
enum MoveToApplications {
    /// Localize using the app's main bundle and the default Localizable.strings table.
    private static func L(_ key: String) -> String {
        // 1) First try normal bundle lookup (default Localizable.strings)
        let primary = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        if primary != key { return primary }

        // 2) Try explicit table name (legacy callers may use table = "Localizable")
        let explicit = Bundle.main.localizedString(forKey: key, value: nil, table: "Localizable")
        if explicit != key { return explicit }

        // 3) Fallback: try to read the Localizable.strings file directly from the preferred .lproj
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        if let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "\(preferred).lproj"),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            // Simple regex to capture: "key" = "value";
            if let regex = try? NSRegularExpression(pattern: "\\\"\(NSRegularExpression.escapedPattern(for: key))\\\"\\s*=\\s*\\\"(.*?)\\\";", options: [.dotMatchesLineSeparators]) {
                let ns = content as NSString
                let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: ns.length))
                if let m = matches.first, m.numberOfRanges >= 2 {
                    let valueRange = m.range(at: 1)
                    let found = ns.substring(with: valueRange)
                    if !found.isEmpty { return found }
                }
            }
        }

        // Debug: print bundle info when nothing found (only in debug builds)
        #if DEBUG
        let bpath = Bundle.main.bundlePath
        let locs = Bundle.main.localizations
        let prefs = Bundle.main.preferredLocalizations
        NSLog("[MoveToApplications] localization miss for key=\(key); bundle=\(bpath) localizations=\(locs) preferred=\(prefs)")
        #endif

        // Last resort: return the key so callers still see something predictable
        return key
    }

    @MainActor static func promptIfNeeded() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { promptIfNeeded() }
            return
        }

        let bundleURL = Bundle.main.bundleURL

        // Respect a user preference to not be asked again.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "MoveToApplications.DoNotAskAgain") { return }

        guard !isInApplicationsFolder(bundleURL) else { return }

        let runningFromDMG = isRunningFromDiskImage(bundleURL)
        let readOnly = isOnReadOnlyVolume(bundleURL)

        // Build alert with optional extra context.
        let alert = NSAlert()
        alert.messageText = L("move.title")

        var info = runningFromDMG ? L("move.info.dmg") : L("move.info.standard")
        if readOnly {
            let suffix = L("move.info.readonlySuffix")
            info.append("\n\n" + suffix)
        }
        alert.informativeText = info

        // Buttons (first is default)
        let moveButton = alert.addButton(withTitle: L("move.button.move")) // .alertFirstButtonReturn
        let skipButton = alert.addButton(withTitle: L("move.button.skip"))         // .alertSecondButtonReturn
        let dontAskButton = alert.addButton(withTitle: L("move.button.dontAsk")) // .alertThirdButtonReturn
        alert.alertStyle = .informational

        // Default/Cancel key equivalents
        moveButton.keyEquivalent = "\r" // Return
        skipButton.keyEquivalent = "\u{1b}" // Escape
        dontAskButton.keyEquivalent = "d" // Convenience

        // Accessory: reveal in Finder after moving
        let revealCheckbox = NSButton(checkboxWithTitle: L("move.checkbox.reveal"), target: nil, action: nil)
        revealCheckbox.state = .off
        alert.accessoryView = revealCheckbox

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // Proceed to move
            break
        case .alertSecondButtonReturn:
            // Skip for now: do nothing
            return
        case .alertThirdButtonReturn:
            // Persist the choice to not ask again
            defaults.set(true, forKey: "MoveToApplications.DoNotAskAgain")
            return
        default:
            return
        }

        // Choose destination (/Applications preferred, else ~/Applications)
        guard let destination = preferredApplicationsFolder() else { return }

        let appName = bundleURL.lastPathComponent
        let destURL = destination.appendingPathComponent(appName, isDirectory: true)

        // If the destination already has an app with the same name, move it to Trash instead of deleting.
        safelyTrashIfExists(at: destURL)

        // Copy the app bundle to the destination (copy rather than move to handle cross-volume).
        do {
            try FileManager.default.copyItem(at: bundleURL, to: destURL)
        } catch {
            presentError(L("error.title.unableToMove"), info: String(format: L("error.info.unableToMove_fmt"), destination.path, error.localizedDescription))
            return
        }

        // Try to remove quarantine attribute from the copied app to avoid extra prompts.
        removeQuarantineAttributes(at: destURL)

        // Reveal in Finder if requested
        if revealCheckbox.state == .on {
            NSWorkspace.shared.activateFileViewerSelecting([destURL])
        }

        // Relaunch the new copy and terminate this one cautiously.
        relaunch(from: destURL)
    }

    // MARK: - Environment Checks

    private static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = url.standardized.path
        if path.hasPrefix("/Applications/") || path == "/Applications" { return true }
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).standardized.path
        if path.hasPrefix(userApps + "/") || path == userApps { return true }
        return false
    }

    private static func isRunningFromDiskImage(_ url: URL) -> Bool {
        let comps = url.standardized.pathComponents
        // Heuristic: running from a mounted volume like /Volumes/Name/...
        return comps.count > 1 && comps[1] == "Volumes"
    }

    private static func isOnReadOnlyVolume(_ url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.volumeIsReadOnlyKey])
            return resourceValues.volumeIsReadOnly ?? false
        } catch {
            return false
        }
    }

    private static func preferredApplicationsFolder() -> URL? {
        let fm = FileManager.default
        let systemApps = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if fm.isWritableFile(atPath: systemApps.path) {
            return systemApps
        }
        let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        if !fm.fileExists(atPath: userApps.path) {
            do { try fm.createDirectory(at: userApps, withIntermediateDirectories: true) } catch { /* ignore */ }
        }
        return userApps
    }

    // MARK: - File Ops

    private static func safelyTrashIfExists(at url: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            // Try to move existing app to Trash. If that fails, fall back to remove.
            if (try? fm.trashItem(at: url, resultingItemURL: nil)) == nil {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func removeQuarantineAttributes(at url: URL) {
        // Best-effort: xattr -dr com.apple.quarantine <app>
        let task = Process()
        task.launchPath = "/usr/bin/xattr"
        task.arguments = ["-dr", "com.apple.quarantine", url.path]
        do { try task.run() } catch { /* ignore */ }
    }

    // MARK: - Relaunch

    private static func relaunch(from newAppURL: URL) {
        let bundleID = (Bundle(url: newAppURL)?.bundleIdentifier) ?? Bundle.main.bundleIdentifier

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: newAppURL, configuration: config) { app, error in
            Task { @MainActor in
                // If we have a bundle id, wait briefly for the new instance to appear, then terminate.
                if let bundleID = bundleID {
                    waitForAppLaunch(bundleIdentifier: bundleID, timeout: 5.0)
                } else {
                    // Fallback: small delay
                    try? await Task.sleep(for: .seconds(1))
                }
                NSApp.terminate(nil)
            }
        }
    }

    @MainActor private static func waitForAppLaunch(bundleIdentifier: String, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            // Consider it launched if there's at least one instance not matching this process id.
            if running.contains(where: { $0.processIdentifier != getpid() }) {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
    }

    // MARK: - UI Helpers

    private static func presentError(_ title: String, info: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("generic.ok"))
        alert.runModal()
    }
}
#endif
