//
//  ContentView.swift
//  CountriesXL
//
//  Created by Tyler Austin on 9/29/25.
//

import SwiftUI
import AuthenticationServices
import Combine

enum ActiveSheet: Identifiable {
    case auth, alerts, conversations, downloads, settings
    var id: Int {
        switch self {
        case .auth: return 0
        case .alerts: return 1
        case .conversations: return 2
        case .downloads: return 3
        case .settings: return 4
        }
    }
}

enum AppearanceChoice: String, CaseIterable {
    case auto, light, dark
}

// Root content for macOS app with a modern sidebar + toolbar and search.
struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var selection: SidebarItem? = .resources
    @State private var searchText: String = ""
    @State private var activeSheet: ActiveSheet? = nil
    @State private var appearance: AppearanceChoice = .auto
    // Connectivity and board state placeholders replaced by new services
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var boardStatus = BoardStatusService.shared
    @State private var showOfflineBanner: Bool = false
    // Removed: @State private var showConnectivityDiagnostics: Bool = false

    @StateObject private var alertsService = AlertsService()
    @StateObject private var conversationsService = ConversationsService()
    @AppStorage("useDownloadManagerSheet") private var useDownloadManagerSheet: Bool = false
    @AppStorage("showDisconnectedOverlay") private var showDisconnectedOverlay: Bool = true
    @State private var showSignInPopover: Bool = false

    // Precomputed values to help the type-checker
    private var preferredScheme: ColorScheme? {
        switch appState.settings.theme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    private var accentTint: Color {
        if let c = appState.settings.accentColor {
            return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        } else {
            return .accentColor
        }
    }

    var body: some View {
        NavigationSplitView {
            let sidebarItems: [SidebarItem] = [.home, .forums, .resources, .media]
            List(sidebarItems, selection: $selection) { item in
                NavigationLink(value: item) {
                    HStack(spacing: 6) {
                        Label(item.title, systemImage: item.systemImage)
                        if !(networkMonitor.isConnected ?? true) {
                            Image(systemName: "wifi.slash").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .navigationTitle("CountriesXL")
        } detail: {
            ZStack {
                detailContent
                overlayView()
            }
            .environmentObject(appState)
            .toolbar { toolbarContent }
            .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search resources, media, threads, users"))
            .onSubmit(of: .search) {
                selection = .search
                appState.searchQuery = searchText
            }
            .onAppear {
                networkMonitor.start()
                Task { await boardStatus.refresh() }
            }
            .sheet(isPresented: $appState.showSettings) {
                SettingsView()
                    .environmentObject(appState)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .alerts:
                    AlertsSheet(alertsService: alertsService)
                case .conversations:
                    ConversationsSheet(conversationsService: conversationsService)
                case .downloads:
                    if useDownloadManagerSheet {
                        DownloadsManagerSheet()
                    } else {
                        DownloadsSheet()
                    }
                case .settings:
                    SettingsView()
                        .environmentObject(appState)
                case .auth:
                    // Reuse existing sign-in flow via settings or profile as appropriate
                    VStack(spacing: 16) {
                        Text("Sign In")
                            .font(.title2)
                        Button("Begin Sign In") { Task { await appState.beginSignInFlow() } }
                    }
                    .padding()
                }
            }
            // Removed sheet for showConnectivityDiagnostics here
            .onReceive(NotificationCenter.default.publisher(for: .openDownloads)) { _ in
                activeSheet = .downloads
            }
            .onReceive(NotificationCenter.default.publisher(for: .openProfile)) { _ in
                selection = .profile
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSignIn)) { _ in
                activeSheet = .auth
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMembership)) { _ in
                #if os(macOS)
                if let url = URL(string: "https://cities-mods.com/account/upgrade") {
                    NSWorkspace.shared.open(url)
                }
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .printDocument)) { _ in
                performPrint()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pageSetup)) { _ in
                performPageSetup()
            }
            .onReceive(NotificationCenter.default.publisher(for: .printCurrentView)) { _ in
                Task { @MainActor in
                    printSwiftUIView(currentDetailPrintableView())
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .printResourcesView)) { _ in
                Task { @MainActor in
                    printSwiftUIView(ResourcesView(appState: appState))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .printMediaView)) { _ in
                Task { @MainActor in
                    printSwiftUIView(MediaView().environmentObject(appState))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .printForumsView)) { _ in
                Task { @MainActor in
                    printSwiftUIView(ForumsView().environmentObject(appState))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .printThreadsView)) { _ in
                Task { @MainActor in
                    // If you have a dedicated ThreadsView, print it; otherwise, reuse ForumsView or Search
                    printSwiftUIView(ForumsView().environmentObject(appState))
                }
            }
            .preferredColorScheme(preferredScheme)
            .popover(isPresented: $showSignInPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                SignInPopoverCard(
                    beginSignIn: { Task { await appState.beginSignInFlow() } },
                    openSettings: { appState.showSettings = true },
                    dismiss: { showSignInPopover = false }
                )
            }
            .tint(accentTint)
        }
        .environmentObject(appState)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Menu {
                if appState.isAuthenticated {
                    // Status header
                    let name = appState.settings.displayName
                    if !name.isEmpty {
                        Text("Signed in as \(name)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Signed in")
                            .foregroundStyle(.secondary)
                    }
                    Divider()

                    Button {
                        selection = .profile
                    } label: {
                        Label("View Profile", systemImage: "person.crop.circle")
                    }
                    .keyboardShortcut("p", modifiers: [.command, .option])

                    Button { activeSheet = .alerts } label: {
                        Label {
                            let c = alertsService.alerts.count
                            Text(c > 0 ? "Alerts (\(c))" : "Alerts")
                        } icon: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                let c = alertsService.alerts.count
                                if c > 0 {
                                    Text(String(min(c, 99)))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color.red)
                                        .clipShape(Capsule())
                                        .offset(x: 6, y: -6)
                                }
                            }
                        }
                    }

                    Button { activeSheet = .conversations } label: {
                        Label {
                            let c = conversationsService.conversations.count
                            Text(c > 0 ? "Conversations (\(c))" : "Conversations")
                        } icon: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "envelope")
                                let c = conversationsService.conversations.count
                                if c > 0 {
                                    Text(String(min(c, 99)))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color.blue)
                                        .clipShape(Capsule())
                                        .offset(x: 6, y: -6)
                                }
                            }
                        }
                    }

                    Button { activeSheet = .downloads } label: { Label("Downloads", systemImage: "arrow.down.circle") }

                    Button {
                        NotificationCenter.default.post(name: .openMembership, object: nil)
                    } label: {
                        Label("Manage Subscription…", systemImage: "creditcard")
                    }

                    Divider()

                    Button { appState.showSettings = true } label: { Label("Settings…", systemImage: "gearshape") }

                    Divider()

                    Button(role: .destructive) {
                        Task { await appState.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Text("Not signed in").foregroundStyle(.secondary)
                    Divider()
                    Button {
                        showSignInPopover = true
                    } label: {
                        Label("Sign In…", systemImage: "person.crop.circle")
                    }
                    Button {
                        if let url = URL(string: "http://cities-mods.com/register") {
                            #if canImport(UIKit)
                            UIApplication.shared.open(url)
                            #elseif os(macOS)
                            NSWorkspace.shared.open(url)
                            #endif
                        }
                    } label: {
                        Label("Create Account…", systemImage: "person.badge.plus")
                    }
                    Divider()
                    Button { appState.showSettings = true } label: { Label("Settings…", systemImage: "gearshape") }
                }
            } label: {
                if appState.isAuthenticated, let avatar = appState.userAvatarImage {
                    Label {
                        let name = appState.settings.displayName
                        Text(name.isEmpty ? "My Account" : name)
                    } icon: {
                        avatar
                            .resizable()
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                    }
                } else {
                    Label("My Account", systemImage: "person.circle")
                }
            }
            .tint(appState.isAuthenticated ? Color.green : Color.accentColor)
            .accessibilityLabel(appState.isAuthenticated ? "My Account" : "Sign In")
            .labelStyle(.titleAndIcon)
            .help(appState.isAuthenticated ? (appState.settings.displayName.isEmpty ? "My Account" : appState.settings.displayName) : "Sign in or create an account")

            Button {
                activeSheet = .alerts
            } label: {
                Label("Alerts", systemImage: "bell")
            }
            .accessibilityLabel("Alerts")
            .labelStyle(.iconOnly)
            .help("View your alerts")
            .keyboardShortcut("1", modifiers: .command)

            Button {
                activeSheet = .conversations
            } label: {
                Label("Conversations", systemImage: "envelope")
            }
            .accessibilityLabel("Conversations")
            .labelStyle(.iconOnly)
            .help("View your conversations")
            .keyboardShortcut("2", modifiers: .command)

            Button {
                activeSheet = .downloads
            } label: {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
            .accessibilityLabel("Downloads")
            .labelStyle(.iconOnly)
            .help("Open Downloads Manager")
            .keyboardShortcut("3", modifiers: .command)
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Menu("Appearance") {
                    Button {
                        appState.settings.theme = .system
                        appearance = .auto
                    } label: {
                        Label("Auto", systemImage: "circle.lefthalf.fill")
                    }
                    Button {
                        appState.settings.theme = .light
                        appearance = .light
                    } label: {
                        Label("Light", systemImage: "sun.max")
                    }
                    Button {
                        appState.settings.theme = .dark
                        appearance = .dark
                    } label: {
                        Label("Dark", systemImage: "moon")
                    }
                }
            } label: {
                Label("Options", systemImage: "gearshape")
            }
            .help("Options")
        }
        ToolbarItem(placement: .primaryAction) {
            if selection == .downloads {
                Button("Clear All") {
                    Task { await DownloadManager.shared.clearAll() }
                }
                .help("Clear all downloads")
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .resources {
        case .home:
            HomeView()
        case .forums:
            ForumsView()
        case .resources:
            ResourcesView(appState: appState)
        case .media:
            MediaView()
        case .search:
            SearchView(query: searchText)
        case .profile:
            ProfileView()
        case .downloads:
            DownloadsView()
        }
    }

    @ViewBuilder
    private func overlayView() -> some View {
        if showDisconnectedOverlay && !(networkMonitor.isConnected ?? true) {
            DisconnectedOverlayView(
                title: "No Internet",
                message: "This app requires access to cities-mods.com.",
                details: networkMonitor.lastError,
                primaryActionTitle: "Try Again",
                primaryAction: { Task { await networkMonitor.checkNow() } },
                secondaryActionTitle: "Close",
                secondaryAction: { /* Simply hide until next state change */ },
                brandingImage: Image("AppLogo"),
                tertiaryActionTitle: "Diagnostics…",
                tertiaryAction: {
                    appState.showSettings = true
                    NotificationCenter.default.post(name: .openSettingsDiagnostics, object: nil)
                },
                brandingSize: 160,
                brandingPlate: true
            )
        } else if showDisconnectedOverlay && (networkMonitor.isConnected ?? false) && !boardStatus.isActive {
            DisconnectedOverlayView(
                title: "Board Inactive",
                message: boardStatus.versionString.isEmpty ? "The forum appears inactive." : "The forum appears inactive (\(boardStatus.versionString)).",
                details: boardStatus.lastError,
                primaryActionTitle: "Try Again",
                primaryAction: { Task { await boardStatus.refresh() } },
                secondaryActionTitle: nil,
                secondaryAction: nil,
                brandingImage: Image("AppLogo"),
                tertiaryActionTitle: "Diagnostics…",
                tertiaryAction: {
                    appState.showSettings = true
                    NotificationCenter.default.post(name: .openSettingsDiagnostics, object: nil)
                },
                brandingSize: 160,
                brandingPlate: true
            )
        }
    }

    private func toggleSidebar() {
        #if os(macOS)
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        #endif
    }

    private func currentDetailPrintableView() -> some View {
        switch selection ?? .resources {
        case .home:
            return AnyView(HomeView().environmentObject(appState))
        case .forums:
            return AnyView(ForumsView().environmentObject(appState))
        case .resources:
            return AnyView(ResourcesView(appState: appState))
        case .media:
            return AnyView(MediaView().environmentObject(appState))
        case .search:
            return AnyView(SearchView(query: searchText).environmentObject(appState))
        case .profile:
            return AnyView(ProfileView().environmentObject(appState))
        case .downloads:
            return AnyView(DownloadsView().environmentObject(appState))
        }
    }

    private func performPrint() {
        #if os(macOS)
        // Print the current detail SwiftUI view using the hardened print utility.
        // Ensure the view has the necessary environment injected.
        let viewToPrint = currentDetailPrintableView()
        printSwiftUIView(viewToPrint)
        #endif
    }

    private func performPageSetup() {
        #if os(macOS)
        guard let window = NSApp.keyWindow else { return }
        let pageLayout = NSPageLayout()
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        // Ensure sane defaults to avoid printToolAgent errors
        if printInfo.paperSize.width <= 0 || printInfo.paperSize.height <= 0 {
            printInfo.paperSize = NSSize(width: 612, height: 792)
        }
        if printInfo.leftMargin < 0 || printInfo.rightMargin < 0 || printInfo.topMargin < 0 || printInfo.bottomMargin < 0 {
            printInfo.leftMargin = 36
            printInfo.rightMargin = 36
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
        }
        pageLayout.beginSheet(with: printInfo, modalFor: window, delegate: nil, didEnd: nil, contextInfo: nil)
        #endif
    }
}

// MARK: - Sidebar Routing

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case forums
    case resources
    case media
    case search
    case profile
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .forums: return "Forums"
        case .resources: return "Resources"
        case .media: return "Media"
        case .search: return "Search"
        case .profile: return "My Profile"
        case .downloads: return "Downloads"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .forums: return "text.bubble"
        case .resources: return "shippingbox"
        case .media: return "photo.on.rectangle.angled"
        case .search: return "magnifyingglass"
        case .profile: return "person.crop.circle"
        case .downloads: return "arrow.down.circle"
        }
    }
}

#Preview {
    ContentView()
}

// MARK: AlertsSheet
struct AlertsSheet: View {
    @ObservedObject var alertsService: AlertsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            if alertsService.isLoading == true {
                ProgressView("Loading Alerts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let error = alertsService.error {
                VStack(spacing: 16) {
                    Text("Failed to load alerts:")
                    Text(error).foregroundColor(.red)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if alertsService.alerts.isEmpty {
                Text("No alerts available.")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(alertsService.alerts) { alert in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .foregroundColor(Color.yellow)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(alert.content)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(alert.createdDate, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(alert.content)")
                    .accessibilityHint("Alert date: \(alert.createdDate.formatted(date: .abbreviated, time: .omitted))")
                }
            }
        }
        .navigationTitle("Alerts")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: ConversationsSheet
struct ConversationsSheet: View {
    @ObservedObject var conversationsService: ConversationsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            if conversationsService.isLoading == true {
                ProgressView("Loading Conversations...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let error = conversationsService.error {
                VStack(spacing: 16) {
                    Text("Failed to load conversations:")
                    Text(error).foregroundColor(.red)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if conversationsService.conversations.isEmpty {
                Text("No conversations available.")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(conversationsService.conversations) { convo in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(Color.blue)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(convo.title)
                                .font(.headline)
                            if let date = convo.lastMessageDate {
                                Text(date, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let replyCount = convo.replyCount {
                                Text("Replies: \(replyCount)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(convo.title)")
                    .accessibilityHint("Last message date: \(convo.lastMessageDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"). Replies: \(convo.replyCount ?? 0)")
                }
            }
        }
        .navigationTitle("Conversations")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: DownloadsSheet
struct DownloadsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = DownloadManagerV2.shared

    var body: some View {
        NavigationStack {
            VStack {
                if manager.downloads.isEmpty {
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle", description: Text("Start a download elsewhere to see it here."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(sortedIds(), id: \.self) { id in
                        if let state = manager.downloads[id] {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(managerTitle(for: id)).font(.headline)
                                    Spacer()
                                    if state.isDownloading {
                                        Text("Downloading").foregroundStyle(.secondary)
                                    } else if state.isPaused {
                                        Text("Paused").foregroundStyle(.secondary)
                                    } else if state.progress >= 1.0 {
                                        Text("Completed").foregroundStyle(.secondary)
                                    } else {
                                        Text("Idle").foregroundStyle(.secondary)
                                    }
                                }
                                ProgressView(value: state.progress)
                                HStack(spacing: 12) {
                                    if state.isDownloading {
                                        Button("Pause") { manager.pauseDownload(id: id) }
                                    } else if state.isPaused {
                                        Button("Resume") { Task { _ = try? await manager.resumeDownload(id: id) } }
                                    } else if state.progress < 1.0 {
                                        Button("Resume") { Task { _ = try? await manager.resumeDownload(id: id) } }
                                    }
                                    Button("Cancel") { manager.cancelDownload(id: id) }
                                    if let fileURL = state.fileURL {
                                        Spacer()
                                        Text(fileURL.lastPathComponent).lineLimit(1)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear All") {
                        let ids = Array(manager.downloads.keys)
                        ids.forEach { manager.clearDownload(id: $0) }
                    }
                }
            }
        }
    }

    private func managerTitle(for id: Int) -> String {
        if let t = manager.title(for: id) { return t }
        return "Download #\(id)"
    }

    private func sortedIds() -> [Int] {
        if let sorted = manager.sortedIds {
            return sorted
        }
        return Array(manager.downloads.keys).sorted()
    }
}

// Placeholder services and models
final class AlertsService: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var alerts: [AlertItem] = []
}

struct AlertItem: Identifiable {
    let id = UUID()
    let content: String
    let createdDate: Date
}

final class ConversationsService: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var conversations: [ConversationItem] = []
}

struct ConversationItem: Identifiable {
    let id = UUID()
    let title: String
    let lastMessageDate: Date?
    let replyCount: Int?
}


private struct SignInPopoverCard: View {
    var beginSignIn: () -> Void
    var openSettings: () -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Sign In").font(.title3).bold()
            Text("Access alerts, conversations, downloads, and more.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Sign In") { beginSignIn(); dismiss() }
                    .buttonStyle(.borderedProminent)
                Button("Settings…") { openSettings(); dismiss() }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        .frame(minWidth: 260)
    }
}


