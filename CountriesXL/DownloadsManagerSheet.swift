import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// A sheet UI that uses DownloadManager with custom Title and URL entry
struct DownloadsManagerSheet: View {
    @ObservedObject private var manager = DownloadManagerV2.shared
    @Environment(\.dismiss) private var dismiss
    @State private var urlString: String = "https://speed.hetzner.de/10MB.bin"
    @State private var titleString: String = "Custom Download"
    @State private var nextID: Int = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Title", text: $titleString)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 8) {
                        TextField("Download URL", text: $urlString)
                            .textFieldStyle(.roundedBorder)
                        #if os(iOS) || os(tvOS) || os(visionOS)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        #endif
                        Button {
                            startDownload()
                        } label: {
                            Label("Start", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)

                if manager.downloads.isEmpty {
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle", description: Text("Enter a URL and tap Start to begin a download."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(sortedIds(), id: \.self) { id in
                        if let state = manager.downloads[id] {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(title(for: id)).font(.headline)
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
                            .contextMenu {
                                if let url = manager.url(for: id) {
                                    Button("Copy URL") {
                                        #if canImport(UIKit)
                                        UIPasteboard.general.string = url.absoluteString
                                        #elseif os(macOS)
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                        #endif
                                    }
                                }
                                #if os(macOS)
                                Button("Reveal in Finder") { manager.revealInFinder(for: id) }
                                #endif
                            }
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

    private func startDownload() {
        guard let url = URL(string: urlString) else { return }
        let id = nextID
        nextID += 1
        let title = titleString.isEmpty ? "Download #\(id)" : titleString
        Task { _ = try? await manager.startDownload(id: id, title: title, url: url) }
    }

    private func sortedIds() -> [Int] {
        if let sorted = manager.sortedIds { return sorted }
        return Array(manager.downloads.keys).sorted()
    }

    private func title(for id: Int) -> String {
        manager.title(for: id) ?? "Download #\(id)"
    }
}
