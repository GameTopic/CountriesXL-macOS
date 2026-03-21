import SwiftUI

struct DownloadButton: View {
    @ObservedObject private var manager = DownloadManagerV2.shared

    private let id: Int
    private let title: String
    private let url: URL
    private let style: ButtonStyleType
    private let descriptor: DownloadManagerV2.DownloadDescriptor
    private let accessibilityIdentifier: String?
    private let onStart: (() -> Void)?
    private var urlProvider: (() async throws -> URL)? = nil
    private var requestProvider: (() async throws -> URLRequest)? = nil

    enum ButtonStyleType { case bordered, borderedProminent, plain }

    init(
        id: Int,
        title: String,
        url: URL,
        style: ButtonStyleType = .bordered,
        descriptor: DownloadManagerV2.DownloadDescriptor = .init(),
        accessibilityIdentifier: String? = nil,
        onStart: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.style = style
        self.descriptor = descriptor
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onStart = onStart
    }

    // Convenience initializer for String-based identifiers
    init(
        id: String,
        title: String,
        url: URL,
        style: ButtonStyleType = .bordered,
        descriptor: DownloadManagerV2.DownloadDescriptor = .init(),
        accessibilityIdentifier: String? = nil,
        onStart: (() -> Void)? = nil
    ) {
        self.id = id.stableIntID
        self.title = title
        self.url = url
        self.style = style
        self.descriptor = descriptor
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onStart = onStart
    }

    // Async URL factory initializer
    init(
        id: Int,
        title: String,
        style: ButtonStyleType = .bordered,
        descriptor: DownloadManagerV2.DownloadDescriptor = .init(),
        accessibilityIdentifier: String? = nil,
        onStart: (() -> Void)? = nil,
        urlProvider: @escaping () async throws -> URL
    ) {
        self.id = id
        self.title = title
        self.url = URL(string: "https://cities-mods.com")! // placeholder; will be replaced by urlProvider at runtime
        self.style = style
        self.descriptor = descriptor
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onStart = onStart
        self.urlProvider = urlProvider
    }

    init(
        id: Int,
        title: String,
        style: ButtonStyleType = .bordered,
        descriptor: DownloadManagerV2.DownloadDescriptor = .init(),
        accessibilityIdentifier: String? = nil,
        onStart: (() -> Void)? = nil,
        requestProvider: @escaping () async throws -> URLRequest
    ) {
        self.id = id
        self.title = title
        self.url = URL(string: "https://cities-mods.com")!
        self.style = style
        self.descriptor = descriptor
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onStart = onStart
        self.requestProvider = requestProvider
    }

    public var body: some View {
        Group {
            if let state = manager.downloads[id] {
                HStack(spacing: 8) {
                    if state.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Preparing")
                            .foregroundStyle(.secondary)
                    } else if state.isQueued {
                        Image(systemName: "tray.full")
                        Text("Queued")
                            .foregroundStyle(.secondary)
                        Button("Open") {
                            NotificationCenter.default.post(name: .openDownloads, object: nil)
                        }
                    } else if state.isDownloading {
                        ProgressView(value: state.progress)
                            .frame(width: 80)
                        Button("Pause") { manager.pauseDownload(id: id) }
                        Button("Cancel") { manager.cancelDownload(id: id) }
                    } else if state.isPaused {
                        Button("Resume") { Task { _ = try? await manager.resumeDownload(id: id) } }
                        Button("Cancel") { manager.cancelDownload(id: id) }
                    } else if state.progress >= 1.0 {
                        Image(systemName: "checkmark.circle")
                        Text("Downloaded")
                        Button("Clear") { manager.clearDownload(id: id) }
                    } else {
                        Button(action: start) {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .accessibilityIdentifier(accessibilityIdentifier ?? "")
                    }
                }
            } else if manager.isCompleted(id: id) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                    Text("Downloaded")
                    Button("Clear") { manager.clearDownload(id: id) }
                }
            } else {
                Button(action: start) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
            }
        }
        .applyStyle(style)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private func start() {
        manager.prepareDownload(id: id, title: title, descriptor: descriptor)
        onStart?()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openDownloads, object: nil)
        }

        Task {
            do {
                if let requestProvider {
                    let request = try await requestProvider()
                    manager.configurePreparedDownload(id: id, request: request, displayURL: request.url)
                } else {
                    let actualURL: URL
                    if let provider = urlProvider {
                        actualURL = try await provider()
                    } else {
                        actualURL = url
                    }
                    var request = URLRequest(url: actualURL)
                    request.httpMethod = "GET"
                    manager.configurePreparedDownload(id: id, request: request, displayURL: actualURL)
                }
            } catch {
                manager.failPreparedDownload(id: id, error: error)
            }
        }
    }

    private var accessibilityLabel: String {
        if let state = manager.downloads[id] {
            if state.isDownloading { return "Downloading \(title)" }
            if state.isPaused { return "Paused \(title)" }
            if state.progress >= 1.0 { return "Downloaded \(title)" }
        }
        if manager.isCompleted(id: id) { return "Downloaded \(title)" }
        return "Download \(title)"
    }

    private var accessibilityHint: String {
        if let state = manager.downloads[id] {
            if state.isDownloading { return "Double-tap to pause or cancel" }
            if state.isPaused { return "Double-tap to resume or cancel" }
            if state.progress >= 1.0 { return "Double-tap to clear entry" }
        }
        if manager.isCompleted(id: id) { return "Double-tap to clear entry" }
        return "Double-tap to start download"
    }
}

private extension View {
    @ViewBuilder
    func applyStyle(_ style: DownloadButton.ButtonStyleType) -> some View {
        switch style {
        case .bordered: self.buttonStyle(.bordered)
        case .borderedProminent: self.buttonStyle(.borderedProminent)
        case .plain: self.buttonStyle(.plain)
        }
    }
}

// MARK: - Stable ID helpers
extension String {
    var stableIntID: Int { Int(bitPattern: UInt(bitPattern: self.hashValue)) }
}

extension UUID {
    var stableIntID: Int { Int(bitPattern: UInt(bitPattern: self.hashValue)) }
}
