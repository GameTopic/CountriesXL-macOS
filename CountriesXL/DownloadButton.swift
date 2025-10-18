import SwiftUI

public struct DownloadButton: View {
    @ObservedObject private var manager = DownloadManagerV2.shared

    private let id: Int
    private let title: String
    private let url: URL
    private let style: ButtonStyleType
    private var urlProvider: (() async throws -> URL)? = nil

    public enum ButtonStyleType { case bordered, borderedProminent, plain }

    public init(id: Int, title: String, url: URL, style: ButtonStyleType = .bordered) {
        self.id = id
        self.title = title
        self.url = url
        self.style = style
    }

    // Convenience initializer for String-based identifiers
    public init(id: String, title: String, url: URL, style: ButtonStyleType = .bordered) {
        self.id = id.stableIntID
        self.title = title
        self.url = url
        self.style = style
    }

    // Async URL factory initializer
    public init(id: Int, title: String, style: ButtonStyleType = .bordered, urlProvider: @escaping () async throws -> URL) {
        self.id = id
        self.title = title
        self.url = URL(string: "https://cities-mods.com")! // placeholder; will be replaced by urlProvider at runtime
        self.style = style
        self.urlProvider = urlProvider
    }

    public var body: some View {
        Group {
            if let state = manager.downloads[id] {
                HStack(spacing: 8) {
                    if state.isDownloading {
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
                    }
                }
            } else {
                Button(action: start) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
        .applyStyle(style)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private func start() {
        Task {
            do {
                let actualURL: URL
                if let provider = urlProvider {
                    actualURL = try await provider()
                } else {
                    actualURL = url
                }
                // Prefer the manager's async start API if available in this target; otherwise enqueue.
                // The call below assumes startDownload is available; if not, you can switch to enqueue in your target.
                _ = try? await manager.startDownload(id: id, title: title, url: actualURL)
            } catch {
                // Silently ignore or log error as needed
            }
        }
    }

    private var accessibilityLabel: String {
        if let state = manager.downloads[id] {
            if state.isDownloading { return "Downloading \(title)" }
            if state.isPaused { return "Paused \(title)" }
            if state.progress >= 1.0 { return "Downloaded \(title)" }
        }
        return "Download \(title)"
    }

    private var accessibilityHint: String {
        if let state = manager.downloads[id] {
            if state.isDownloading { return "Double-tap to pause or cancel" }
            if state.isPaused { return "Double-tap to resume or cancel" }
            if state.progress >= 1.0 { return "Double-tap to clear entry" }
        }
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
public extension String {
    var stableIntID: Int { Int(bitPattern: UInt(bitPattern: self.hashValue)) }
}

public extension UUID {
    var stableIntID: Int { Int(bitPattern: UInt(bitPattern: self.hashValue)) }
}
