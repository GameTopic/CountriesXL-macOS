import Foundation
import AppKit

@objc public final class XFMGMediaAPIPlugin: PluginBase {
    public override var pluginName: String { "XFMG Media API" }

    public override func register(with manager: PluginManager) {
        // Register any defaults required for remote API integration
        let defaults: [String: Any] = [
            "xfmgBaseURL": "https://cities-mods.com",
            "xfmgAPIToken": ""
        ]
        UserDefaults.standard.register(defaults: defaults)
    }

    private static let _registered: Void = {
        PluginManager.shared.registerPresence(name: "XFMG Media API")
    }()
}
