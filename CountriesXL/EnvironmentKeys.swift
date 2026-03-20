import SwiftUI

private struct HelpWindowCloserKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct XenForoAPIKey: EnvironmentKey {
    static let defaultValue: XenForoAPI = XenForoAPI()
}

extension EnvironmentValues {
    var helpWindowCloser: (() -> Void)? {
        get { self[HelpWindowCloserKey.self] }
        set { self[HelpWindowCloserKey.self] = newValue }
    }

    var xfAPI: XenForoAPI {
        get { self[XenForoAPIKey.self] }
        set { self[XenForoAPIKey.self] = newValue }
    }
}

@MainActor
func callHelpWindowCloser(_ closer: (() -> Void)?, fallback: () -> Void) {
    if let closer {
        closer()
    } else {
        fallback()
    }
}
