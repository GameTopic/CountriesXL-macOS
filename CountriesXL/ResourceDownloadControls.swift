import SwiftUI
import Combine

// Reusable per-row download controls for resources and attachments
public struct ResourceDownloadControls: View {
    @ObservedObject private var manager = DownloadManagerV2.shared
    private let id: Int
    private let title: String
    private let urlProvider: () async throws -> URL

    public init(id: Int, title: String, urlProvider: @escaping () async throws -> URL) {
        self.id = id
        self.title = title
        self.urlProvider = urlProvider
    }

    public var body: some View {
        if let state = manager.downloads[id] {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 8) {
                    if state.progress > 0 && state.progress < 1 {
                        ProgressView(value: state.progress)
                            .frame(width: 100)
                        Text("\(Int(state.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let sizeText = manager.fileSizeText(for: id) {
                            Text(sizeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if state.isDownloading {
                        Button("Pause") { manager.pauseDownload(id: id) }
                            .buttonStyle(.bordered)
                    } else if state.isPaused {
                        Button("Resume") { Task { _ = try? await manager.resumeDownload(id: id) } }
                            .buttonStyle(.borderedProminent)
                    } else if state.progress >= 1.0 {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Button("Clear") { manager.clearDownload(id: id) }
                            .buttonStyle(.bordered)
                    } else {
                        DownloadButton(id: id, title: title, style: .bordered, urlProvider: urlProvider)
                    }
                }
                Text(manager.statusText(for: id))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            DownloadButton(id: id, title: title, style: .bordered, urlProvider: urlProvider)
        }
    }
}

