import SwiftUI

// Register these commands from your App type via:
// .commands { HelpCommands() }

struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Button("What’s New") {
                NotificationCenter.default.post(name: .openWhatsNew, object: nil)
            }
            .keyboardShortcut("N", modifiers: [.command, .shift])

            Button("Guide") {
                NotificationCenter.default.post(name: .openGuide, object: nil)
            }
            .keyboardShortcut("?", modifiers: [.command])

            Button("Tour") {
                NotificationCenter.default.post(name: .openTour, object: nil)
            }
        }
    }
}
