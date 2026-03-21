//
//  CountriesXLApp.swift
//  CountriesXL
//
//  Created by Tyler Austin on 9/29/25.
//

import SwiftUI
import SwiftData
import AuthenticationServices
import CoreLocation

@main
struct CountriesXLApp: App {
    init() {
        configureUITestStateIfNeeded()
#if os(macOS)
        // Offer to move the app to /Applications on first launch if needed.
        if !ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            MoveToApplications.promptIfNeeded()
        }
        
        if UserDefaults.standard.bool(forKey: "updatesCheckOnLaunch") {
            // Delay slightly to allow app to finish launching
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                SparkleUpdater.shared.checkForUpdates()
            }
        }
        
        if UserDefaults.standard.bool(forKey: "updatesAutoInstall") {
            // This is a placeholder. Actual silent install requires appropriate Sparkle user driver configuration.
            // We simply persist the preference here.
        }
#endif
    }
    
    @StateObject private var appState = AppState()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    AuthManager.shared.handleIncomingURL(url)
                }
                .task {
                    if #available(macOS 26.0, *) {
                        LocationService.shared.requestAuthorizationAndStart()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .commands {
            AppCommands(appState: appState)
            HelpCommands()
        }
#endif
    }
}

private extension CountriesXLApp {
    func configureUITestStateIfNeeded() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ui-testing") else { return }

        if arguments.contains("-ui-test-seed-preparing-download") {
            DownloadManagerV2.shared.seedPreparedDownloadForTesting()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationCenter.default.post(name: .openDownloads, object: nil)
            }
        } else if arguments.contains("-ui-test-seed-queued-download") {
            DownloadManagerV2.shared.seedQueuedDownloadForTesting()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationCenter.default.post(name: .openDownloads, object: nil)
            }
        } else if arguments.contains("-ui-test-seed-completed-download") {
            DownloadManagerV2.shared.seedCompletedDownloadForTesting()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationCenter.default.post(name: .openDownloads, object: nil)
            }
        } else {
            DownloadManagerV2.shared.resetForTesting()
        }
        #endif
    }
}

#if DEBUG
enum UITestLaunchConfiguration {
    private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    static var opensResourceOverviewDownloadScenario: Bool {
        arguments.contains("-ui-test-resource-overview-download")
    }

    static var seededResourceNavigationContext: ResourceNavigationContext {
        ResourceNavigationContext(
            resource: XFResource(
                id: 328,
                title: "Lake City - Small Firehall",
                iconURL: nil,
                coverURL: nil,
                fileSize: nil,
                category: "Civic Services",
                rating: nil,
                ratingCount: nil,
                releaseDate: nil,
                updatedDate: nil,
                downloadCount: nil,
                viewCount: nil,
                tagLine: "UI test seeded resource overview.",
                versionString: nil,
                authorName: nil,
                summary: "UI test seeded resource overview.",
                descriptionBBCode: nil,
                installInstructions: nil,
                viewURL: URL(string: "https://cities-mods.com/resources/328/"),
                screenshots: [],
                fields: [],
                updates: [],
                reviews: [],
                videos: [],
                relatedResources: [],
                attachmentURLs: [:]
            ),
            fallbackRelatedResources: []
        )
    }

    static func resourceOverviewDownloadRequest() -> URLRequest {
        let fileURL = temporaryDownloadFixtureURL()
        return URLRequest(url: fileURL)
    }

    private static func temporaryDownloadFixtureURL() -> URL {
        let fixtureURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CountriesXL-UITest-Resource-Download.zip")

        if !FileManager.default.fileExists(atPath: fixtureURL.path) {
            let data = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00])
            try? data.write(to: fixtureURL, options: .atomic)
        }

        return fixtureURL
    }
}
#endif

#if os(macOS)
private struct AppCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
        }
        
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        
        CommandGroup(replacing: .printItem) {
            Button("Print…") { NotificationCenter.default.post(name: .printDocument, object: nil) }
                .keyboardShortcut("p", modifiers: .command)
            Button("Page Setup…") { NotificationCenter.default.post(name: .pageSetup, object: nil) }
            Divider()
            Button("Print Current View…") { NotificationCenter.default.post(name: .printCurrentView, object: nil) }
        }
        
        CommandMenu("Downloads") {
            Button("Open Downloads…") {
                NotificationCenter.default.post(name: .openDownloads, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandMenu("Account") {
            if appState.isAuthenticated {
                let name = appState.settings.displayName
                Text(name.isEmpty ? "Signed in" : name)
                    .foregroundStyle(.secondary)
                Divider()
            } else {
                Text("Not signed in")
                    .foregroundStyle(.secondary)
                Divider()
            }

            if appState.isAuthenticated {
                Button("Open Profile") {
                    NotificationCenter.default.post(name: .openProfile, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button("Sign Out", role: .destructive) {
                    Task { await appState.signOut() }
                }
                .keyboardShortcut("s", modifiers: [.command, .option, .shift])
            } else {
                Button("Sign In") {
                    NotificationCenter.default.post(name: .openSignIn, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
        }
        
#if os(macOS)
        CommandGroup(after: .help) {
            Button("Check for Updates…") {
                SparkleUpdater.shared.checkForUpdates()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
        }
#endif
    }
}
#endif

extension Notification.Name {
    static let openAlerts = Notification.Name("CountriesXL.openAlerts")
    static let openConversations = Notification.Name("CountriesXL.openConversations")
    static let openDownloads = Notification.Name("CountriesXL.openDownloads")
    static let openProfile = Notification.Name("CountriesXL.openProfile")
    static let openSignIn = Notification.Name("CountriesXL.openSignIn")
    static let openSettings = Notification.Name("CountriesXL.openSettings")
    static let printDocument = Notification.Name("CountriesXL.printDocument")
    static let pageSetup = Notification.Name("CountriesXL.pageSetup")
    static let printCurrentView = Notification.Name("CountriesXL.printCurrentView")
    static let printResourcesView = Notification.Name("CountriesXL.printResourcesView")
    static let printMediaView = Notification.Name("CountriesXL.printMediaView")
    static let printForumsView = Notification.Name("CountriesXL.printForumsView")
    static let printThreadsView = Notification.Name("CountriesXL.printThreadsView")
    static let openMembership = Notification.Name("CountriesXL.openMembership")
}
