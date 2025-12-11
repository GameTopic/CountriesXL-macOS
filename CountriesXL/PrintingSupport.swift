import Foundation
#if os(macOS)
import AppKit

extension NSResponder {
    @objc func print(_ sender: Any?) {
        NotificationCenter.default.post(name: .printDocument, object: nil)
    }

    @objc func runPageLayout(_ sender: Any?) {
        NotificationCenter.default.post(name: .pageSetup, object: nil)
    }
}
#endif
