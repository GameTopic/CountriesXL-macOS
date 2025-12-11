import Foundation
import AppKit

@objc public final class DRMPlaybackPlugin: PluginBase {
    public override var pluginName: String { "DRM Playback" }

    public override func register(with manager: PluginManager) {
        // Register DRM-specific defaults
        let defaults: [String: Any] = [
            "drmLicenseEndpoint": "",
            "drmPlaybackEnabled": false
        ]
        UserDefaults.standard.register(defaults: defaults)
    }

    private static let _registered: Void = {
        PluginManager.shared.registerPresence(name: "DRM Playback")
    }()
}
