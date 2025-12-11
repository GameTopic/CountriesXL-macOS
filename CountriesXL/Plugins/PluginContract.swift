import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// A minimal, Objective-C visible interface that the host app's plugin manager should conform to.
/// Using a protocol here avoids ambiguous type lookup while keeping the contract stable for plugins.
@objc(CXLPluginManaging) public protocol PluginManaging: AnyObject {
    /// Optionally expose minimal hooks that plugins can call during registration.
    /// Keep this surface area small to avoid coupling. You can extend this protocol in your host app target.
    /// For example:
    /// - func register(menuItemWithTitle title: String, action: Selector, target: AnyObject?)
}

@MainActor
@objcMembers
@objc(CXLPluginBase) open class PluginBase: NSObject {
    /// A human-readable name for the plugin. Subclasses should override to provide a meaningful name.
    @objc open var pluginName: String { "Unnamed Plugin" }

    /// Called on the main actor during app startup. Perform lightweight registration and UI hook setup here.
    @objc open func register(with manager: PluginManaging) {
        // Default no-op
    }

    /// Called on the main actor when the host is unloading the plugin or tearing down UI. Default no-op.
    @objc open func deregister(from manager: PluginManaging) {
        // Default no-op
    }

    // Required initializer so metatype-based construction (principalClass.init()) compiles for subclasses
    @objc public required override init() {
        super.init()
    }
}

