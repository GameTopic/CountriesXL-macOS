import SwiftUI
#if os(macOS)
import AppKit

/// Print any SwiftUI view by rendering it into an NSHostingView and
/// sending it to the print system with sane defaults.
@MainActor
func printSwiftUIView<Content: View>(_ content: Content, title: String? = nil) {
    // Build a hosting view for the SwiftUI content
    let hosting = NSHostingView(rootView: content)

    // Ask SwiftUI to size the content at its ideal size
    let targetSize = hosting.fittingSize
    let size = targetSize.width > 0 && targetSize.height > 0 ? targetSize : NSSize(width: 612, height: 792)
    hosting.setFrameSize(size)

    // Validate print info to avoid printToolAgent errors
    let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
    printInfo.horizontalPagination = .automatic
    printInfo.verticalPagination = .automatic
    printInfo.isHorizontallyCentered = true
    printInfo.isVerticallyCentered = true
    if printInfo.paperSize.width <= 0 || printInfo.paperSize.height <= 0 {
        printInfo.paperSize = NSSize(width: 612, height: 792) // Letter
    }
    if printInfo.leftMargin < 0 || printInfo.rightMargin < 0 || printInfo.topMargin < 0 || printInfo.bottomMargin < 0 {
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
    }

    // Create and run the print operation modally for the key window if available
    let op = NSPrintOperation(view: hosting, printInfo: printInfo)
    op.showsPrintPanel = true
    op.showsProgressPanel = true
    if let window = NSApp.keyWindow {
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    } else {
        op.run()
    }
}

#endif
