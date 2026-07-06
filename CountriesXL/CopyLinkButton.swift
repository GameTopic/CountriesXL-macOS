import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct CopyLinkButton: View {
    let url: URL
    var title: String = "Copy Link"
    var copiedTitle: String = "Copied"

    @State private var copied = false

    var body: some View {
        Button {
            copy(url)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(copied ? copiedTitle : title, systemImage: copied ? "checkmark" : "link")
        }
        .accessibilityLabel(copied ? copiedTitle : title)
    }

    private func copy(_ url: URL) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = url.absoluteString
        #endif
    }
}
