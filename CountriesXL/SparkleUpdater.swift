import Foundation

#if os(macOS)
#if canImport(Sparkle)
import Sparkle
#endif

/// Sparkle integration for macOS using Sparkle 2's SPUStandardUpdaterController,
/// with support for switching between stable and beta feeds.
final class SparkleUpdater: NSObject {
    static let shared = SparkleUpdater()

    #if canImport(Sparkle)
    private lazy var controller: SPUStandardUpdaterController = {
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()
#endif // canImport(Sparkle)

    private override init() {
        #if canImport(Sparkle)
        super.init()
        #else
        super.init()
        #endif
    }

    /// Manually trigger a check for updates (e.g., from a menu item).
    func checkForUpdates() {
        #if canImport(Sparkle)
        controller.checkForUpdates(nil)
        #endif
    }

    /// Returns the effective feed URL string Sparkle will use right now, or nil if not configured.
    func currentFeedURLString() -> String? {
        #if canImport(Sparkle)
        // Mirror logic from the delegate
        let useBeta = UserDefaults.standard.bool(forKey: "updatesUseBeta")
        if useBeta, let beta = Bundle.main.object(forInfoDictionaryKey: "SUBetaFeedURL") as? String, !beta.isEmpty {
            return beta
        }
        if let stable = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, !stable.isEmpty {
            return stable
        }
        return nil
        #else
        return nil
        #endif
    }

    /// Exposes Sparkle's automaticallyDownloadsUpdates setting to the Settings UI.
    var automaticallyDownloadsUpdates: Bool {
        get {
            #if canImport(Sparkle)
            return controller.updater.automaticallyDownloadsUpdates
            #else
            return UserDefaults.standard.bool(forKey: "SparkleAutomaticallyDownloadsUpdates")
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller.updater.automaticallyDownloadsUpdates = newValue
            #else
            UserDefaults.standard.set(newValue, forKey: "SparkleAutomaticallyDownloadsUpdates")
            #endif
        }
    }

    // MARK: - Helpers for Settings UI
    /// Returns true if a beta feed URL is configured in Info.plist (SUBetaFeedURL).
    func isBetaFeedAvailable() -> Bool {
        if let beta = Bundle.main.object(forInfoDictionaryKey: "SUBetaFeedURL") as? String, !beta.isEmpty {
            return true
        }
        return false
    }

    /// Returns the active channel string ("Beta" or "Stable") based on the user default and availability.
    func activeChannel() -> String {
        let useBeta = UserDefaults.standard.bool(forKey: "updatesUseBeta")
        if useBeta && isBetaFeedAvailable() {
            return "Beta"
        }
        return "Stable"
    }

    /// Exposes Sparkle's automaticallyChecksForUpdates setting to the Settings UI.
    var automaticallyChecksForUpdates: Bool {
        get {
            #if canImport(Sparkle)
            return controller.updater.automaticallyChecksForUpdates
            #else
            return UserDefaults.standard.bool(forKey: "SparkleAutomaticallyChecksForUpdates")
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller.updater.automaticallyChecksForUpdates = newValue
            #else
            UserDefaults.standard.set(newValue, forKey: "SparkleAutomaticallyChecksForUpdates")
            #endif
        }
    }

    /// Preference to automatically install updates when possible.
    /// Note: Actual behavior depends on Sparkle's user driver and app policy.
    var automaticallyInstallsUpdates: Bool {
        get {
            // Prefer Sparkle property if available in your configuration; otherwise use a stored preference.
            #if canImport(Sparkle)
            // If SPUUpdater exposes `automaticallyInstallsUpdates`, use it; otherwise fall back to UserDefaults.
            // Commented out direct access to avoid build errors on configurations without this API.
            // return controller.updater.automaticallyInstallsUpdates
            #endif
            return UserDefaults.standard.bool(forKey: "updatesAutoInstall")
        }
        set {
            #if canImport(Sparkle)
            // If SPUUpdater exposes `automaticallyInstallsUpdates`, set it; otherwise persist.
            // controller.updater.automaticallyInstallsUpdates = newValue
            #endif
            UserDefaults.standard.set(newValue, forKey: "updatesAutoInstall")
        }
    }
}

#if canImport(Sparkle)
extension SparkleUpdater: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        // Prefer a beta feed when the user has opted in and when a beta feed is configured.
        let useBeta = UserDefaults.standard.bool(forKey: "updatesUseBeta")
        let betaKey = "SUBetaFeedURL"
        let stableKey = "SUFeedURL"
        if useBeta, let beta = Bundle.main.object(forInfoDictionaryKey: betaKey) as? String, !beta.isEmpty {
            return beta
        }
        if let stable = Bundle.main.object(forInfoDictionaryKey: stableKey) as? String, !stable.isEmpty {
            return stable
        }
        return nil
    }
}
#endif

#endif

