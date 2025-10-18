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
        UserDefaults.standard.register(defaults: [
            "useDownloadManagerSheet": false
        ])
        
#if os(macOS)
        // Offer to move the app to /Applications on first launch if needed.
        MoveToApplications.promptIfNeeded()
        
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
                    LocationService.shared.requestAuthorizationAndStart()
                }
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .commands {
            AppCommands(appState: appState)
        }
#endif
#if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
#endif
    }
}

#if os(macOS)
private struct AppCommands: Commands {
    @ObservedObject var appState: AppState
    @AppStorage("useDownloadManagerSheet") private var useDownloadManagerSheet: Bool = false

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
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

        CommandGroup(after: .toolbar) {
            Toggle("Use Download Manager for Downloads Sheet", isOn: $useDownloadManagerSheet)
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
    static let openDownloads = Notification.Name("CountriesXL.openDownloads")
    static let openProfile = Notification.Name("CountriesXL.openProfile")
    static let openSignIn = Notification.Name("CountriesXL.openSignIn")
    static let printDocument = Notification.Name("CountriesXL.printDocument")
    static let pageSetup = Notification.Name("CountriesXL.pageSetup")
    static let printCurrentView = Notification.Name("CountriesXL.printCurrentView")
    static let printResourcesView = Notification.Name("CountriesXL.printResourcesView")
    static let printMediaView = Notification.Name("CountriesXL.printMediaView")
    static let printForumsView = Notification.Name("CountriesXL.printForumsView")
    static let printThreadsView = Notification.Name("CountriesXL.printThreadsView")
    static let openMembership = Notification.Name("CountriesXL.openMembership")
}
