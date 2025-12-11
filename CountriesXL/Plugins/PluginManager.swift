import Foundation
import AppKit

@objc(PluginManagerHost) public final class PluginHostManager: NSObject, PluginManaging {
    public static let shared = PluginHostManager()
    private override init() { super.init() }

    private(set) var loadedPlugins = [PluginBase]()
    private var presenceSet = Set<String>()
    private let presenceQueue = DispatchQueue(label: "PluginManager.presenceQueue")

    /// Register presence for a plugin by name. Safe to call multiple times.
    public func registerPresence(name: String) {
        presenceQueue.sync { _ = presenceSet.insert(name) }
    }

    /// Returns whether a plugin is present (either loaded as a bundle or registered statically).
    public func hasPlugin(_ name: String) -> Bool {
        let present = presenceQueue.sync { presenceSet.contains(name) }
        return present || loadedPlugins.contains(where: { $0.pluginName == name })
    }

    /// Loads plugin bundles from the app's "Plugins" directory inside Application Support or the app bundle's PlugIns
    public func loadPlugins() {
        var candidateURLs = [URL]()

        // 1. App bundle PlugIns
        if let bundlePluginsURL = Bundle.main.builtInPlugInsURL {
            candidateURLs.append(bundlePluginsURL)
        }

        // 2. Application Support/Plugins
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let pluginsDir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "CountriesXL").appendingPathComponent("Plugins")
            candidateURLs.append(pluginsDir)
        }

        for dir in candidateURLs {
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension == "plugin" || item.pathExtension == "bundle" {
                if let bundle = Bundle(url: item), bundle.load() {
                    if let principal = bundle.principalClass as? PluginBase.Type {
                        let plugin = principal.init()
                        plugin.register(with: self)
                        loadedPlugins.append(plugin)
                        // Register presence by plugin name for UI discovery
                        presenceQueue.sync { _ = presenceSet.insert(plugin.pluginName) }
                        NSLog("Loaded plugin: \(plugin.pluginName)")
                    }
                }
            }
        }
    }

    public func pluginNamed(_ name: String) -> PluginBase? {
        return loadedPlugins.first { $0.pluginName == name }
    }
}

