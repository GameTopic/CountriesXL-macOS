// SettingsView.swift
// User Preferences for App
import SwiftUI
import Combine
import AppKit
import WebKit
import ServiceManagement
import LocalAuthentication
import UniformTypeIdentifiers
import CoreLocation
import OSLog

enum SidebarTab: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case privacy = "Privacy"
    case notifications = "Notifications"
    case pwaManifest = "PWA Manifest"
    case pwaSetup = "PWA Setup"
    case account = "Account"
    case advanced = "Advanced"
    case experimental = "Experimental"
    case downloads = "Downloads"
    case updates = "Updates"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .privacy: return "hand.raised"
        case .notifications: return "bell"
        case .pwaManifest: return "doc.text.magnifyingglass"
        case .pwaSetup: return "square.and.arrow.down"
        case .account: return "person.crop.circle"
        case .advanced: return "wrench"
        case .experimental: return "flask"
        case .downloads: return "arrow.down.circle"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SidebarTab? = .general
    @StateObject private var settings = SettingsStore()
    @State private var lastError: Error?
    @State private var applyErrorMessage: String?
    @State private var hoveredTab: SidebarTab? = nil

    @State private var searchText: String = ""

    private var filteredTabs: [SidebarTab] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SidebarTab.allCases }
        return SidebarTab.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(q) }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: "Settings")

    var body: some View {
        NavigationSplitView {
            List(filteredTabs, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.iconName)
                    .tag(tab)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    .fontWeight(selectedTab == tab ? .semibold : .regular)
                    .foregroundColor(selectedTab == tab ? .primary : (hoveredTab == tab ? .primary.opacity(0.9) : .primary))
                    .background(
                        Group {
                            if selectedTab == tab {
                                Color.accentColor.opacity(0.08)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .overlay(alignment: .leading) {
                        if selectedTab == tab {
                            Color.accentColor
                                .frame(width: 3)
                                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                    .onHover { isHovering in
                        hoveredTab = isHovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
                    }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .onAppear {
                if selectedTab == nil { selectedTab = filteredTabs.first ?? .general }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, selectedTab == nil {
                    selectedTab = .general
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenUpdatesSettingsTab"))) { _ in
                selectedTab = .updates
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: Text("Search Settings"))
            .onChange(of: searchText) { _, _ in
                // If the current selection is filtered out, select the first available tab
                if let sel = selectedTab, !filteredTabs.contains(sel) {
                    selectedTab = filteredTabs.first
                }
            }
        } detail: {
            Group {
                switch (selectedTab ?? .general) {
                case .general:
                    GeneralSettingsView()
                        .environmentObject(settings)
                case .appearance:
                    AppearanceSettingsView()
                        .environmentObject(settings)
                case .privacy:
                    PrivacySettingsView()
                        .environmentObject(settings)
                case .notifications:
                    NotificationsSettingsView()
                        .environmentObject(settings)
                case .pwaManifest:
                    PWAManifestSettingsView()
                case .pwaSetup:
                    PWASetupSettingsView()
                case .account:
                    AccountSettingsView()
                        .environmentObject(settings)
                case .advanced:
                    AdvancedSettingsView()
                        .environmentObject(settings)
                case .experimental:
                    ExperimentalSettingsView()
                        .environmentObject(settings)
                case .downloads:
                    DownloadsSettingsView()
                        .environmentObject(settings)
                case .updates:
                    UpdatesSettingsView()
                        .environmentObject(settings)
                }
            }
            .padding()
            .task {
                if settings.directoryCreationPrompt == nil {
                    settings.directoryCreationPrompt = { path in
                        await promptCreateFolder(path: path)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button("OK") {
                        Task { @MainActor in
                            do {
                                try await settings.apply()
                                dismiss()
                            } catch {
                                logger.error("Failed to apply settings: \(error.localizedDescription, privacy: .public)")
                                lastError = error
                                applyErrorMessage = [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Cancel") {
                        settings.cancel()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Apply") {
                        Task { @MainActor in
                            do {
                                try await settings.apply()
                                dismiss()
                            } catch {
                                logger.error("Failed to apply settings: \(error.localizedDescription, privacy: .public)")
                                lastError = error
                                applyErrorMessage = [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
                            }
                        }
                    }
                }
                .padding([.horizontal, .bottom])
                .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .alert("Couldn’t Apply Settings", isPresented: Binding(get: { applyErrorMessage != nil }, set: { if !$0 { applyErrorMessage = nil; lastError = nil } })) {
            Button("Copy Details") { copyErrorDetails() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(applyErrorMessage ?? "")
        }
        .onChange(of: applyErrorMessage) { _, newValue in
            if let msg = newValue {
                logger.info("Presenting settings apply error alert with message: \(msg, privacy: .public)")
            }
        }
        .removeSidebarToggleIfAvailable()
        .makeSettingsToolbarlessOnMac()
    }

    private func copyErrorDetails() {
        let description = applyErrorMessage ?? lastError?.localizedDescription ?? "Unknown error"
        let suggestion = (lastError as? LocalizedError)?.recoverySuggestion
        var details = description
        if let s = suggestion, !s.isEmpty {
            details += "\n\nSuggestion: \(s)"
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(details, forType: .string)
    }

    private func promptCreateFolder(path: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Create folder?"
            alert.informativeText = "The folder \"\(path)\" does not exist. Do you want to create it?"
            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            if let window = NSApp.keyWindow ?? NSApp.windows.first {
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            } else {
                DispatchQueue.main.async {
                    let response = alert.runModal()
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            }
        }
    }
}

// MARK: - General Tab

private struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    private let languageOptions = [
        "English (US / CA)",
        "English (UK)",
        "Spanish (Spain)",
        "French (France)",
        "German (Germany)"
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Autoplay Video", isOn: $settings.draft.videoAutoplayEnabled)

                Toggle("Start at Login", isOn: $settings.draft.startAtLogin)
            }

            Section(header: Text("Language / Region")) {
                Picker("Language / Region", selection: $settings.draft.languageRegion) {
                    ForEach(languageOptions, id: \.self) { lang in
                        Text(lang)
                    }
                }
                .pickerStyle(DefaultPickerStyle())
            }

            Section(header: Text("Download Location")) {
                HStack {
                    Text(settings.draft.downloadPath.isEmpty ? "Default" : settings.draft.downloadPath)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FilePickerButton(title: "Choose…") { url in
                        settings.draft.downloadPath = url?.path ?? ""
                        // Note: For sandboxed apps, convert URL to security-scoped bookmark and store that instead.
                    }
                }
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    settings.resetToDefaults()
                }
                Text("Restores all preferences to their factory values. This action can’t be undone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Updates")) {
                Button("Open Updates Preferences…") {
                    // Switch the selection to the Updates tab if available
                    NotificationCenter.default.post(name: Notification.Name("OpenUpdatesSettingsTab"), object: nil)
                }
                .help("Manage update preferences including channels and automatic behavior.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Privacy Tab
private struct PrivacySettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    // Biometric authentication is immediate and not persisted
    @State private var biometricLockEnabled: Bool = false
    @State private var biometricAlert: BiometricAlert? = nil
    @State private var showConfirmClearData: Bool = false
    @State private var showConfirmAppReset: Bool = false
    @State private var privacyToastMessage: String? = nil

    struct BiometricAlert: Identifiable {
        let id = UUID()
        let message: String
    }

    var body: some View {
        Form {
            Section {
                Toggle(LocalizedStringKey("privacy.pushNotifications"), isOn: $settings.draft.pushNotificationsEnabled)
                Toggle(LocalizedStringKey("privacy.location"), isOn: $settings.draft.locationEnabled)
                    .onChange(of: settings.draft.locationEnabled) { _, newValue in
                        if newValue { LocationService.shared.requestAuthorizationAndStart() } else { LocationService.shared.stop() }
                    }
                Toggle(LocalizedStringKey("privacy.disableAds"), isOn: $settings.draft.adsDisabled)
                Toggle(LocalizedStringKey("privacy.disableVideoAds"), isOn: $settings.draft.disableVideoAds)
                    .disabled(settings.draft.adsDisabled)
                    .help(LocalizedStringKey("privacy.disableVideoAds.help"))
            }

            Section {
                Toggle(LocalizedStringKey("privacy.biometric"), isOn: Binding(
                     get: { biometricLockEnabled },
                     set: { newValue in
                         if newValue { authenticateBiometricLock(enable: true) } else { authenticateBiometricLock(enable: false) }
                     }
                 ))

                Toggle(LocalizedStringKey("privacy.sendAnonymousUsageData"), isOn: $settings.draft.sendAnonymousUsageData)

                Button(LocalizedStringKey("privacy.clearCache"), role: .destructive) { showConfirmClearData = true }
                Button(LocalizedStringKey("privacy.resetApp"), role: .destructive) { showConfirmAppReset = true }
                    .help(LocalizedStringKey("privacy.resetApp.help"))
                Text(LocalizedStringKey("privacy.clearCacheInfo"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(LocalizedStringKey("privacy.appPermissions"))) {
                Toggle(LocalizedStringKey("privacy.notifications"), isOn: .constant(true)).disabled(true)
                Toggle(LocalizedStringKey("privacy.filesAccess"), isOn: .constant(false)).disabled(true)
                Toggle(LocalizedStringKey("privacy.locationAccess"), isOn: .constant(true)).disabled(true)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert(item: $biometricAlert) { alert in
            Alert(title: Text(LocalizedStringKey("privacy.biometric")), message: Text(alert.message), dismissButton: .default(Text(LocalizedStringKey("generic.ok"))))
        }
        .confirmationDialog(LocalizedStringKey("privacy.clearCache"), isPresented: $showConfirmClearData, titleVisibility: .visible) {
            Button(LocalizedStringKey("button.clear"), role: .destructive) {
                clearCachesAndTemporaryFiles()
                privacyToastMessage = NSLocalizedString("privacy.cacheCleared", comment: "Cache cleared toast")
            }
            Button(LocalizedStringKey("button.cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("privacy.clearCacheInfo"))
        }
        .confirmationDialog(LocalizedStringKey("privacy.resetApp"), isPresented: $showConfirmAppReset, titleVisibility: .visible) {
            Button(LocalizedStringKey("privacy.resetApp"), role: .destructive) {
                performAppReset()
                privacyToastMessage = NSLocalizedString("privacy.resetComplete", comment: "Reset complete")
            }
            Button(LocalizedStringKey("button.cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("privacy.resetApp.help"))
        }
        .overlay(alignment: .bottomTrailing) {
            if let msg = privacyToastMessage {
                Text(msg)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .padding()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: privacyToastMessage)
    }

    private func authenticateBiometricLock(enable: Bool) {
        let context = LAContext()
        context.localizedCancelTitle = NSLocalizedString("button.cancel", comment: "Cancel")
        var error: NSError?

        let policy: LAPolicy = .deviceOwnerAuthentication

        if context.canEvaluatePolicy(policy, error: &error) {
            let reason = enable ? NSLocalizedString("privacy.enableBiometric", comment: "Enable biometric reason") : NSLocalizedString("privacy.disableBiometric", comment: "Disable biometric reason")
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    if success { biometricLockEnabled = enable } else { biometricLockEnabled = !enable; biometricAlert = BiometricAlert(message: NSLocalizedString("privacy.biometricAuthFailed", comment: "Auth failed")) }
                }
            }
        } else {
            DispatchQueue.main.async { biometricAlert = BiometricAlert(message: NSLocalizedString("privacy.biometricUnavailable", comment: "Unavailable")); biometricLockEnabled = !enable }
        }
    }

    private func clearCachesAndTemporaryFiles() {
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        if let caches = try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            if let contents = try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil, options: []) {
                for url in contents { try? fm.removeItem(at: url) }
            }
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        if let contents = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil, options: []) {
            for url in contents { try? fm.removeItem(at: url) }
        }
    }

    private func performAppReset() {
        clearCachesAndTemporaryFiles()
        if let bundleID = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: bundleID); UserDefaults.standard.synchronize() }
    }
}

// MARK: - Appearance Tab
private struct AppearanceSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    enum ColorSchemeOption: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"
        case system = "System"
        var id: String { rawValue }
    }

    enum AccentColorOption: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case red = "Red"
        case green = "Green"
        case orange = "Orange"
        case purple = "Purple"
        case pink = "Pink"
        case yellow = "Yellow"
        var id: String { rawValue }

        var color: Color {
            switch self {
            case .blue: return .blue
            case .red: return .red
            case .green: return .green
            case .orange: return .orange
            case .purple: return .purple
            case .pink: return .pink
            case .yellow: return .yellow
            }
        }
    }

    enum FontSizeOption: String, CaseIterable, Identifiable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section(header: Text("Color Scheme")) {
                Picker("Color Scheme", selection: $settings.draft.colorSchemeSelection) {
                    ForEach(ColorSchemeOption.allCases) { option in
                        Text(option.rawValue).tag(AppColorScheme(rawValue: option.rawValue) ?? .system)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            Section(header: Text("Accent Color")) {
                Picker("Accent Color", selection: $settings.draft.accentColorSelection) {
                    ForEach(AccentColorOption.allCases) { option in
                        HStack {
                            Circle().fill(option.color).frame(width: 20, height: 20)
                            Text(option.rawValue)
                        }
                        .tag(AppAccentColor(rawValue: option.rawValue) ?? .blue)
                    }
                }
                .pickerStyle(DefaultPickerStyle())
            }

            Section(header: Text("Font Size")) {
                Picker("Font Size", selection: $settings.draft.fontSizeSelection) {
                    ForEach(FontSizeOption.allCases) { option in
                        Text(option.rawValue).tag(AppFontSize(rawValue: option.rawValue) ?? .medium)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            Section(header: Text("Window Transparency")) {
                Slider(value: $settings.draft.windowTransparency, in: 0...100, step: 1) {
                    Text("Transparency")
                }
                Text("\(Int(settings.draft.windowTransparency))%")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Notifications Tab
private struct NotificationsSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    enum NotificationSound: String, CaseIterable, Identifiable {
        case none = "None"
        case `default` = "Default"
        case custom = "Custom"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section(header: Text("Notification Sound")) {
                Picker("Sound", selection: $settings.draft.notificationSound) {
                    ForEach(NotificationSound.allCases) { sound in
                        Text(sound.rawValue).tag(AppNotificationSound(rawValue: sound.rawValue) ?? .default)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            Section {
                Toggle("Badge App Icon", isOn: $settings.draft.badgeAppIcon)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Account Tab
private struct AccountSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Button("Change Profile Picture / Avatar") {
                    // Profile picture/avatar change functionality
                }

                TextField("Display Name", text: $settings.draft.displayName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Toggle("Two-Factor Authentication", isOn: $settings.draft.twoFactorAuthEnabled)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    // Sign out functionality
                }
                Text("You’ll need to sign in again to access your account features.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Advanced Tab
private struct AdvancedSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var showFolderPicker = false

    var body: some View {
        Form {
            Section(header: Text("Custom Data Directory")) {
                HStack {
                    Text(settings.draft.customDataDirectory.isEmpty ? "Default" : settings.draft.customDataDirectory)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") {
                        showFolderPicker = true
                    }
                }
                .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [UTType.folder], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        if let folder = urls.first {
                            settings.draft.customDataDirectory = folder.path
                            // Note: For sandboxed apps, store a security-scoped bookmark instead of a raw path.
                        }
                    default:
                        break
                    }
                }
                Text("Demo only: No real directory change.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("Developer Mode", isOn: $settings.draft.developerModeEnabled)
            }

            Section(header: Text("Proxy Configuration")) {
                TextField("Proxy Address (host:port)", text: $settings.draft.proxyConfiguration)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Experimental Tab
private struct ExperimentalSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    private enum SheetMode: Identifiable { case feedback, diagnostics; var id: Int { hashValue } }
    @State private var sheetMode: SheetMode? = nil

    var body: some View {
        Form {
            Section {
                Toggle("Beta Features", isOn: $settings.draft.betaFeaturesEnabled)
                Toggle("Show Integration Status in Media", isOn: $settings.draft.showIntegrationStatusInfo)
            }
            
            Section(header: Text("Connectivity Overlay")) {
                Toggle("Show Disconnected Overlay", isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "showDisconnectedOverlay") as? Bool ?? true },
                    set: { newValue in UserDefaults.standard.set(newValue, forKey: "showDisconnectedOverlay") }
                ))
                .help("When disabled, the app will not show the full-screen disconnected overlay. Quick alerts will still appear in views.")
            }

            Section {
                Button("Feedback") { sheetMode = .feedback }
                Button("Diagnostics…") { sheetMode = .diagnostics }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(item: $sheetMode) { mode in
            switch mode {
            case .feedback:
                FeedbackFormView(isPresented: Binding(
                    get: { sheetMode != nil },
                    set: { if !$0 { sheetMode = nil } }
                ))
            case .diagnostics:
                SettingsDiagnosticsView()
                    .environmentObject(settings)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsDiagnostics)) { _ in
            sheetMode = .diagnostics
        }
    }
}

// MARK: - Downloads Tab
private struct DownloadsSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage("downloadProgressDisplay") private var downloadProgressDisplay: String = "bytes" // "bytes" or "eta"
    @AppStorage("downloadShowRate") private var downloadShowRate: Bool = true
    @AppStorage("downloadShowRateLastKnown") private var downloadShowRateLastKnown: Bool = true

    var body: some View {
        Form {
            Section(header: Text("Progress Display")) {
                Picker("Show in Downloads", selection: $downloadProgressDisplay) {
                    Text("Downloaded bytes").tag("bytes")
                    Text("Remaining time").tag("eta")
                }
                .pickerStyle(.segmented)
                .help("Choose whether to show downloaded bytes or remaining time in the Downloads view.")

                Toggle("Show Transfer Rate", isOn: $downloadShowRate)
                    .onChange(of: downloadShowRate) { _, newValue in
                        downloadShowRateLastKnown = newValue
                    }
                    .help("Show current transfer rate next to ETA in Downloads view.")
                    .disabled(downloadProgressDisplay == "bytes")
            }

            Section(header: Text("History")) {
                HStack(spacing: 12) {
                    Button("Clear Download History (Legacy)", role: .destructive) {
                        Task { await DownloadManager.shared.clearAll() }
                    }
                    Button("Clear Download History (Manager V2)", role: .destructive) {
                        if let ids = DownloadManagerV2.shared.sortedIds {
                            ids.forEach { DownloadManagerV2.shared.clearDownload(id: $0) }
                        } else {
                            let ids = Array(DownloadManagerV2.shared.downloads.keys)
                            ids.forEach { DownloadManagerV2.shared.clearDownload(id: $0) }
                        }
                    }
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: downloadProgressDisplay) { _, newValue in
            if newValue == "bytes" {
                downloadShowRate = false
            } else if newValue == "eta" {
                downloadShowRate = downloadShowRateLastKnown
            }
        }
    }
}

// MARK: - Updates Tab
private struct UpdatesSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage("updatesUseBeta") private var updatesUseBeta: Bool = false
    @State private var autoChecks: Bool = SparkleUpdater.shared.automaticallyChecksForUpdates
    @State private var autoDownloads: Bool = SparkleUpdater.shared.automaticallyDownloadsUpdates
    @State private var currentFeed: String = SparkleUpdater.shared.currentFeedURLString() ?? ""

    @State private var draftAutoChecks: Bool = false
    @State private var draftAutoDownloads: Bool = false
    @State private var draftCheckOnLaunch: Bool = false
    @State private var draftAutoInstall: Bool = false

    var body: some View {
        Form {
            Section {
                Button("Check for Updates…") {
                    SparkleUpdater.shared.checkForUpdates()
                }
            }

            Section(header: Text("Channel")) {
                let betaAvailable = SparkleUpdater.shared.isBetaFeedAvailable()
                Toggle("Receive Beta Updates", isOn: $updatesUseBeta)
                    .disabled(!betaAvailable)
                    .onChange(of: updatesUseBeta) { _, _ in
                        // No-op; SparkleUpdater reads the preference when checking feed URL.
                    }
                HStack {
                    Text("Current: \(SparkleUpdater.shared.activeChannel())")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !betaAvailable {
                        Text("Beta feed not configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !currentFeed.isEmpty {
                    Text("Feed: \(currentFeed)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section(header: Text("Automatic Updates")) {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { draftAutoChecks },
                    set: { newValue in
                        draftAutoChecks = newValue
                        settings.draft.updatesAutoChecks = newValue
                        SparkleUpdater.shared.automaticallyChecksForUpdates = newValue
                    }
                ))
                .help("When enabled, Sparkle will periodically check for updates in the background.")
            }

            Section(header: Text("Download Behavior")) {
                Toggle("Automatically download updates", isOn: Binding(
                    get: { draftAutoDownloads },
                    set: { newValue in
                        draftAutoDownloads = newValue
                        settings.draft.updatesAutoDownloads = newValue
                        SparkleUpdater.shared.automaticallyDownloadsUpdates = newValue
                    }
                ))
                .help("When enabled, Sparkle will automatically download available updates.")
            }

            Section(header: Text("Installation")) {
                Toggle("Automatically install updates", isOn: Binding(
                    get: { draftAutoInstall },
                    set: { newValue in
                        draftAutoInstall = newValue
                        settings.draft.updatesAutoInstall = newValue
                        SparkleUpdater.shared.automaticallyInstallsUpdates = newValue
                    }
                ))
                .help("When enabled and supported by your update policy, updates may install automatically without prompts.")
            }

            Section(header: Text("On Launch")) {
                Toggle("Check for updates on launch", isOn: Binding(
                    get: { draftCheckOnLaunch },
                    set: { newValue in
                        draftCheckOnLaunch = newValue
                        settings.draft.updatesCheckOnLaunch = newValue
                        UserDefaults.standard.set(newValue, forKey: "updatesCheckOnLaunch")
                    }
                ))
                .help("If enabled, a manual check for updates will run each time the app launches.")
            }

            Section {
                Button("Reset Update Preferences") {
                    draftAutoChecks = false
                    draftAutoDownloads = false
                    draftCheckOnLaunch = false
                    draftAutoInstall = false
                    updatesUseBeta = false

                    settings.draft.updatesAutoChecks = false
                    settings.draft.updatesAutoDownloads = false
                    settings.draft.updatesCheckOnLaunch = false
                    settings.draft.updatesAutoInstall = false
                    UserDefaults.standard.set(false, forKey: "updatesUseBeta")

                    SparkleUpdater.shared.automaticallyChecksForUpdates = false
                    SparkleUpdater.shared.automaticallyDownloadsUpdates = false
                    SparkleUpdater.shared.automaticallyInstallsUpdates = false
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            draftAutoChecks = settings.draft.updatesAutoChecks
            draftAutoDownloads = settings.draft.updatesAutoDownloads
            draftCheckOnLaunch = settings.draft.updatesCheckOnLaunch
            draftAutoInstall = settings.draft.updatesAutoInstall
            autoChecks = SparkleUpdater.shared.automaticallyChecksForUpdates
            autoDownloads = SparkleUpdater.shared.automaticallyDownloadsUpdates
            currentFeed = SparkleUpdater.shared.currentFeedURLString() ?? ""
        }
        .onChange(of: updatesUseBeta) { _, _ in
            currentFeed = SparkleUpdater.shared.currentFeedURLString() ?? ""
        }
    }
}

// MARK: - Feedback Form View
private struct FeedbackFormView: View {
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var message: String = ""
    @State private var screenshotURL: URL? = nil
    @State private var showFileImporter = false

    struct FeedbackAlert: Identifiable { let id = UUID(); let message: String }
    @State private var alertMessage: FeedbackAlert? = nil

    @State private var nameError: String? = nil
    @State private var emailError: String? = nil
    @State private var messageError: String? = nil

    @State private var isSending: Bool = false
    @State private var showSuccess: Bool = false

    private let minMessageLength = 6

    var body: some View {
        VStack {
            if showSuccess {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.green)
                        .accessibilityHidden(true)
                    Text("Thank you for your feedback!")
                        .font(.title3)
                        .bold()
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Button("Close") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Close feedback form")
                }
                Spacer()
            } else {
                Text("Send Feedback")
                    .font(.title2)
                    .bold()
                    .padding(.bottom, 16)
                    .accessibilityAddTraits(.isHeader)

                Form {
                    Section(header: Text("Your Info")) {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: $name)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .textContentType(.name)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(nameError != nil ? Color.red : Color.clear, lineWidth: 1))
                                .accessibilityLabel("Name")
                                .disableAutocorrection(true)
                                .onChange(of: name) { _, _ in validateInline() }
                            if let error = nameError { Text(error).foregroundColor(.red).font(.caption) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Email", text: $email)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .textContentType(.emailAddress)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(emailError != nil ? Color.red : Color.clear, lineWidth: 1))
                                .accessibilityLabel("Email")
                                .disableAutocorrection(true)
                                .onChange(of: email) { _, _ in validateInline() }
                            if let error = emailError { Text(error).foregroundColor(.red).font(.caption) }
                        }
                    }

                    Section(header: Text("Message")) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextEditor(text: $message)
                                .frame(minHeight: 120)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(messageError != nil ? Color.red : Color.gray.opacity(0.3), lineWidth: 1))
                                .accessibilityLabel("Feedback message")
                                .onChange(of: message) { _, _ in validateInline() }
                            HStack {
                                if let error = messageError { Text(error).foregroundColor(.red).font(.caption) }
                                Spacer()
                                Text("\(message.count) characters")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section(header: Text("Screenshot (optional)")) {
                        HStack {
                            if let url = screenshotURL {
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .accessibilityLabel("Selected screenshot file \(url.lastPathComponent)")
                                Spacer()
                                Button { screenshotURL = nil } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .accessibilityLabel("Remove screenshot")
                            } else {
                                Text("No image selected").foregroundColor(.secondary)
                                Spacer()
                            }
                            Button("Choose…") { showFileImporter = true }
                                .accessibilityLabel("Choose screenshot image")
                        }
                    }
                }
                .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.image], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        screenshotURL = urls.first
                    case .failure(let error):
                        alertMessage = FeedbackAlert(message: "Image selection failed: \(error.localizedDescription)")
                    }
                }
                .padding(.bottom)

                HStack {
                    Button("Cancel") { isPresented = false }
                    Spacer()
                    Button(action: { validateAndSend() }) {
                        if isSending { ProgressView().frame(width: 24, height: 24) } else { Text("Send") }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSending || !isFormValid())
                    .help("Send feedback via your default Mail app")
                }
                .padding([.horizontal, .bottom])
            }
        }
        .padding()
        .frame(minWidth: 450, minHeight: 420)
        .alert(item: $alertMessage) { alert in
            Alert(title: Text("Feedback"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Validation & Sending

    private func validateInline() {
        nameError = nil; emailError = nil; messageError = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { nameError = "Name is required." }
        if trimmedEmail.isEmpty { emailError = "Email is required." }
        else if !isValidEmail(trimmedEmail) { emailError = "Please enter a valid email address." }
        if trimmedMessage.isEmpty || trimmedMessage.count < minMessageLength {
            messageError = "Message is required (\(minMessageLength)+ characters)."
        }
    }

    private func validateAndSend() {
        validateInline()
        guard isFormValid() else { return }
        sendFeedback()
    }

    private func isFormValid() -> Bool {
        guard !isSending else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let validName = !trimmedName.isEmpty
        let validEmail = !trimmedEmail.isEmpty && isValidEmail(trimmedEmail)
        let validMessage = !trimmedMessage.isEmpty && trimmedMessage.count >= minMessageLength
        return validName && validEmail && validMessage
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegEx)
        return predicate.evaluate(with: email)
    }

    private func sendFeedback() {
        isSending = true
        let feedbackEmail = "feedback@cities-mods.com"
        let subject = "App Feedback: CountriesXL - macOS"
        let bodyText = """
        Name: \(name.trimmingCharacters(in: .whitespacesAndNewlines))
        Email: \(email.trimmingCharacters(in: .whitespacesAndNewlines))

        Message:
        \(message.trimmingCharacters(in: .whitespacesAndNewlines))
        """

        var items: [Any] = []
        if let url = screenshotURL { items.append(url) }
        items.append(NSMutableString(string: bodyText))

        if let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: items) {
            service.recipients = [feedbackEmail]
            service.subject = subject
            service.perform(withItems: items)
            showSuccessUI()
        } else {
            let bodyEncoded = bodyText
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
                .replacingOccurrences(of: "\n", with: "%0A") ?? ""
            let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "App%20Feedback"
            if let mailtoURL = URL(string: "mailto:\(feedbackEmail)?subject=\(subjectEncoded)&body=\(bodyEncoded)") {
                NSWorkspace.shared.open(mailtoURL)
                showSuccessUI()
            } else {
                alertMessage = FeedbackAlert(message: "Failed to create mailto URL.")
                isSending = false
            }
        }
    }

    private func showSuccessUI() {
        DispatchQueue.main.async {
            isSending = false
            showSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isPresented = false
            }
        }
    }
}

// MARK: - PWA Manifest Tab (Placeholder)
struct PWAManifestSettingsView: View {
    @State private var manifestURL: String = ""
    @State private var lastFetched: Date? = nil
    @State private var fetchError: String? = nil

    var body: some View {
        Form {
            Section(header: Text("Manifest URL")) {
                TextField("https://example.com/manifest.webmanifest", text: $manifestURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            Section {
                Button("Fetch Manifest") {
                    fetchError = nil
                    lastFetched = Date()
                }
                if let last = lastFetched {
                    Text("Last fetched: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let err = fetchError {
                    Text(err).foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - PWA Setup Tab (Placeholder)
struct PWASetupSettingsView: View {
    @State private var installToDock: Bool = true
    @State private var createDesktopShortcut: Bool = false
    @State private var selectedIcon: String = "Default"

    var body: some View {
        Form {
            Section(header: Text("Installation Options")) {
                Toggle("Install to Dock", isOn: $installToDock)
                Toggle("Create Desktop Shortcut", isOn: $createDesktopShortcut)
            }
            Section(header: Text("Icon")) {
                Picker("Icon", selection: $selectedIcon) {
                    Text("Default").tag("Default")
                    Text("Monochrome").tag("Monochrome")
                    Text("High Contrast").tag("High Contrast")
                }
            }
            Section {
                Button("Install PWA") {
                    // Placeholder action
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Helpers

private struct FilePickerButton: View {
    let title: String
    var onPick: (URL?) -> Void

    @State private var showPicker = false

    var body: some View {
        Button(title) {
            showPicker = true
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [UTType.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                onPick(urls.first)
            case .failure:
                onPick(nil)
            }
        }
    }
}

private struct SettingsDiagnosticsView: View {
    @EnvironmentObject private var settings: SettingsStore

    @State private var accessResult: String = ""
    @State private var showFolderPicker = false
    @State private var showApplyConfirm = false

    @State private var accessOK: Bool? = nil
    @State private var applyDiagError: String? = nil
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let ok = accessOK {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(ok ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ok ? "Download folder access OK" : "Download folder access failed")
                            .bold()
                        Text(accessResult.isEmpty ? (ok ? "Security-scoped bookmark appears valid." : "No folder configured or access failed.") : accessResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Refresh") { refreshStatus() }
                        .keyboardShortcut("r", modifiers: [.command])
                        .help("Re-check bookmark validity and access permissions")
                }
                .padding(10)
                .background((ok ? Color.green.opacity(0.12) : Color.orange.opacity(0.12)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text("Diagnostics").font(.title2).bold()
            Form {
                Section(header: Text("Download Folder")) {
                    let url = settings.resolveDownloadURL()
                    Text(url?.path ?? "Not set")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    HStack {
                        Button("Choose…") { showFolderPicker = true }
                        Button("Test Access") { testAccess() }
                        Button("Reveal in Finder") { revealInFinder() }
                            .disabled(url == nil)
                        Button("Use Default Downloads Folder") { setDefaultDownloads() }
                            .disabled(url != nil)
                    }
                    .onAppear { refreshStatus() }
                    .onChange(of: settings.draft.downloadPath) { _, _ in
                        refreshStatus()
                    }
                    Button("Clear Bookmark") { showClearConfirm = true }
                        .buttonStyle(.bordered)
                        .help("Remove the saved security-scoped bookmark and clear the selected path")
                    if !accessResult.isEmpty {
                        Text(accessResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Section(header: Text("Login Item")) {
                    Text("Status: \(settings.loginItemStatusString())")
                    HStack {
                        Button("Register") { setLoginItem(true) }
                        Button("Unregister") { setLoginItem(false) }
                    }
                    Text("Make sure the helper is embedded and identifier is set in Info.plist.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Apply Download Changes") { showApplyConfirm = true }
                Button("Close") { closeWindow() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [UTType.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let folder = urls.first {
                    settings.draft.downloadPath = folder.path
                }
            case .failure(let error):
                // Surface importer failure to the banner area
                accessOK = false
                accessResult = "Folder selection failed: \(error.localizedDescription)"
            }
        }
        .alert("Couldn’t Apply", isPresented: Binding(get: { applyDiagError != nil }, set: { if !$0 { applyDiagError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(applyDiagError ?? "")
        }
        .confirmationDialog("Clear Bookmark?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                settings.clearDownloadBookmark(resetPath: true)
                refreshStatus()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the saved bookmark and clear the selected download folder path.")
        }
        .confirmationDialog("Apply Download Changes?", isPresented: $showApplyConfirm, titleVisibility: .visible) {
            Button("Apply", role: .none) {
                Task { @MainActor in
                    do {
                        try await settings.apply()
                        refreshStatus()
                    } catch {
                        applyDiagError = [error.localizedDescription, (error as? LocalizedError)?.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will apply your current settings, including any changes to the download folder.")
        }
    }

    // MARK: - Actions

    private func testAccess() {
        let url = settings.beginAccessingDownloadFolder()
        defer { settings.endAccessingDownloadFolder(url) }
        if let u = url {
            accessOK = true
            accessResult = "Access OK: \(u.path)"
        } else {
            accessOK = false
            accessResult = "No folder configured or access failed."
        }
    }

    private func revealInFinder() {
        guard let url = settings.resolveDownloadURL() else { return }
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    private func setDefaultDownloads() {
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            settings.draft.downloadPath = downloads.path
        }
    }

    private func refreshStatus() {
        let url = settings.beginAccessingDownloadFolder()
        defer { settings.endAccessingDownloadFolder(url) }
        if let u = url {
            accessOK = true
            accessResult = "Access OK: \(u.path)"
        } else {
            accessOK = false
            accessResult = "No folder configured or access failed."
        }
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            try settings.setLoginItemEnabled(enabled)
        } catch {
            applyDiagError = error.localizedDescription
        }
    }

    private func closeWindow() {
        #if os(macOS)
        NSApp.keyWindow?.close()
        #endif
    }
}

#Preview {
    SettingsView()
}

#Preview("Appearance") {
    AppearanceSettingsView().environmentObject(SettingsStore())
}

#Preview("Notifications") {
    NotificationsSettingsView().environmentObject(SettingsStore())
}

#Preview("Privacy") {
    PrivacySettingsView().environmentObject(SettingsStore())
}

#Preview("Advanced") {
    AdvancedSettingsView().environmentObject(SettingsStore())
}

#Preview("Downloads") {
    DownloadsSettingsView().environmentObject(SettingsStore())
}

#Preview("Diagnostics") {
    SettingsDiagnosticsView().environmentObject(SettingsStore())
}

#Preview("Feedback") {
    FeedbackFormView(isPresented: .constant(true))
}

// Conditional toolbar removal helper for macOS
private extension View {
    @ViewBuilder
    func removeSidebarToggleIfAvailable() -> some View {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            // Remove the synthesized sidebar toggle where supported
            self
                .toolbar(removing: .sidebarToggle)
                // Also occupy the navigation placement so SwiftUI doesn't synthesize it in edge cases
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        EmptyView().frame(width: 0, height: 0).hidden()
                    }
                }
        } else {
            // On older macOS, occupy the navigation placement to prevent synthesis
            self.toolbar {
                ToolbarItem(placement: .navigation) {
                    EmptyView().frame(width: 0, height: 0).hidden()
                }
            }
        }
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window ?? NSApp.keyWindow {
                // Remove the toolbar entirely so no sidebar toggle can be synthesized
                window.toolbar = nil
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = false
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { }
}

private extension View {
    func makeSettingsToolbarlessOnMac() -> some View {
        self.background(SettingsWindowConfigurator())
    }
}
#endif
