// LocalizationManager.swift
import Foundation
import Combine
import ObjectiveC

private final class BundleKey: NSObject {}
private let bundleKey: UnsafeMutableRawPointer = Unmanaged.passUnretained(BundleKey()).toOpaque()

private final class BundleLanguageProxy: Bundle, @unchecked Sendable {
    nonisolated override init?(path: String) {
        super.init(path: path)
    }

    nonisolated override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let langBundle = objc_getAssociatedObject(self, bundleKey) as? Bundle {
            return langBundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    @MainActor
    private static func ensureSwizzled() {
        #if DEBUG
        assert(Thread.isMainThread, "Bundle swizzling must occur on main thread")
        #endif
        // Only swizzle once by checking class type
        if !(Bundle.main is BundleLanguageProxy) {
            object_setClass(Bundle.main, BundleLanguageProxy.self)
        }
    }

    @MainActor static func setLanguage(_ code: String?) {
        ensureSwizzled()
        if let code = code, !code.isEmpty,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            objc_setAssociatedObject(Bundle.main, bundleKey, langBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } else {
            objc_setAssociatedObject(Bundle.main, bundleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    static let languageChangedNotification = Notification.Name("LocalizationManager.languageChanged")

    @Published private(set) var currentLanguage: String? = nil

    private init() {
        // Read persisted override if any
        if let code = UserDefaults.standard.string(forKey: "SettingsStore.languageOverride") {
            currentLanguage = code
            Bundle.setLanguage(code)
        } else {
            currentLanguage = nil
            Bundle.setLanguage(nil)
        }
    }

    func setLanguage(_ code: String?) {
        if let c = code, c.isEmpty {
            setLanguage(nil)
            return
        }
        currentLanguage = code
        if let c = code {
            UserDefaults.standard.set(c, forKey: "SettingsStore.languageOverride")
            Bundle.setLanguage(c)
        } else {
            UserDefaults.standard.removeObject(forKey: "SettingsStore.languageOverride")
            Bundle.setLanguage(nil)
        }
        NotificationCenter.default.post(name: LocalizationManager.languageChangedNotification, object: code)
    }
}
