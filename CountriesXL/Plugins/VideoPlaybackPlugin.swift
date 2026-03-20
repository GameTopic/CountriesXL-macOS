import Foundation
import AppKit

@objc public final class VideoPlaybackPlugin: PluginBase {
    public override var pluginName: String { "Video Playback" }

    public override func register(with manager: PluginManaging) {
        // Example: register user defaults for plugin settings
        let defaults: [String: Any] = [
            "mediaPreferredQuality": "auto",
            "mediaAutoplayEnabled": false,
            "mediaSubtitlesEnabled": true,
            "mediaAdsEnabled": false
        ]
        UserDefaults.standard.register(defaults: defaults)
    }

    // Static registration for compiled-in plugin presence
    private static let _registered: Void = {
        PluginHostManager.shared.registerPresence(name: "Video Playback")
    }()
}
