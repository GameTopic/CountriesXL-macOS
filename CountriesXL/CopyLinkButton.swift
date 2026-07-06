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
            ClipboardWriter.copy(url.absoluteString)
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
}

struct CopyItemListButton: View {
    let items: [SavedItem]
    var title: String = "Copy List"
    var copiedTitle: String = "Copied"

    @State private var copied = false

    private var exportText: String {
        items.map { item in
            if let url = item.shareURL {
                return "- [\(item.title)](\(url.absoluteString))"
            }

            return "- \(item.title)"
        }
        .joined(separator: "\n")
    }

    var body: some View {
        Button {
            ClipboardWriter.copy(exportText)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(copied ? copiedTitle : title, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .disabled(items.isEmpty)
        .accessibilityLabel(copied ? copiedTitle : title)
    }
}

enum ClipboardWriter {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
