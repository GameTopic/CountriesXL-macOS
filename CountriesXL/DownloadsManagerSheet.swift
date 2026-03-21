import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DownloadsManagerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DownloadsBrowser(showsManualEntry: false, showsCloseButton: true) {
                dismiss()
            }
        }
    }
}

struct DownloadsBrowser: View {
    @ObservedObject private var manager = DownloadManagerV2.shared
    @State private var urlString: String = "https://speed.hetzner.de/10MB.bin"
    @State private var titleString: String = "Custom Download"
    @State private var nextID: Int = 1

    let showsManualEntry: Bool
    let showsCloseButton: Bool
    let onClose: (() -> Void)?

    init(
        showsManualEntry: Bool,
        showsCloseButton: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        self.showsManualEntry = showsManualEntry
        self.showsCloseButton = showsCloseButton
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 12) {
            infoHeader

            if showsManualEntry {
                manualEntrySection
            }

            DownloadsList()

            if let destination = SettingsStore().resolveDownloadURL() {
                Text("Downloads save to \(destination.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose?()
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Clear All") {
                    manager.knownDownloadIDs.forEach { manager.clearDownload(id: $0) }
                }
                .disabled(!manager.hasKnownDownloads)
            }
        }
        .alert(item: $manager.activeAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    private var infoHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Queued downloads appear here before saving.")
                .font(.subheadline.weight(.medium))
            Text("Use Save to download to the app's default folder, or Save As to choose a location.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var manualEntrySection: some View {
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

                Button("Queue") {
                    queueManualDownload()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
    }

    private func queueManualDownload() {
        guard let url = URL(string: urlString) else { return }
        let id = nextID
        nextID += 1
        let title = titleString.isEmpty ? "Download #\(id)" : titleString
        let descriptor = DownloadManagerV2.DownloadDescriptor(kind: .generic, sourceTitle: "Manual")
        manager.queueDownload(id: id, title: title, url: url, descriptor: descriptor)
    }
}

struct DownloadsList: View {
    @ObservedObject private var manager = DownloadManagerV2.shared

    var body: some View {
        if !manager.hasKnownDownloads {
            VStack(alignment: .leading, spacing: 8) {
                Text("No downloads yet")
                    .font(.headline)
                Text("Resource, media, and file downloads will show up here after you press Download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Completed files stay available for Run, Install, Save As, or Delete File.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal)
            .padding(.top, 8)
        } else {
            List(manager.knownDownloadIDs, id: \.self) { id in
                DownloadRow(id: id)
            }
            .listStyle(.inset)
        }
    }
}

private struct DownloadRow: View {
    @ObservedObject private var manager = DownloadManagerV2.shared

    let id: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.title(for: id) ?? "Download #\(id)")
                        .font(.headline)

                    if let fileURL = manager.fileURL(for: id) {
                        Text(fileURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let url = manager.url(for: id) {
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(manager.statusText(for: id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressValue)

            HStack(spacing: 10) {
                controls
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var controls: some View {
        if manager.isCompleted(id: id) {
            #if os(macOS)
            Button(manager.actionTitle(for: id)) {
                manager.openDownloadedFile(for: id)
            }
            Button("Save As") {
                manager.saveDownloadAs(for: id)
            }
            #endif
            Button("Delete File") {
                #if os(macOS)
                manager.deleteDownloadedFile(for: id)
                #else
                manager.clearDownload(id: id)
                #endif
            }
        } else if let state = manager.downloads[id], state.isPreparing {
            ProgressView()
                .controlSize(.small)
            Text("Preparing download link…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel") {
                manager.cancelDownload(id: id)
            }
        } else if let state = manager.downloads[id], state.isQueued {
            Button("Save") {
                Task { if manager.canStartQueuedDownload(id: id) { _ = try? await manager.startQueuedDownload(id: id) } }
            }
            .accessibilityIdentifier("download-save-\(id)")
            .disabled(!manager.canStartQueuedDownload(id: id))
            #if os(macOS)
            Button("Save As") {
                Task { if manager.canStartQueuedDownload(id: id) { await manager.startQueuedDownloadWithSavePanel(for: id) } }
            }
            .accessibilityIdentifier("download-save-as-\(id)")
            .disabled(!manager.canStartQueuedDownload(id: id))
            #endif
            Button("Cancel") {
                manager.cancelDownload(id: id)
            }
            .accessibilityIdentifier("download-cancel-\(id)")
        } else if let state = manager.downloads[id], state.isDownloading {
            Button("Pause") {
                manager.pauseDownload(id: id)
            }
            Button("Cancel") {
                manager.cancelDownload(id: id)
            }
        } else if let state = manager.downloads[id], state.isPaused {
            Button("Resume") {
                Task { _ = try? await manager.resumeDownload(id: id) }
            }
            Button("Cancel") {
                manager.cancelDownload(id: id)
            }
        } else {
            Button("Save") {
                Task { _ = try? await manager.startQueuedDownload(id: id) }
            }
            .accessibilityIdentifier("download-save-\(id)")
            Button("Cancel") {
                manager.cancelDownload(id: id)
            }
            .accessibilityIdentifier("download-cancel-\(id)")
        }
    }

    private var progressValue: Double {
        if let state = manager.downloads[id] {
            return state.progress
        }
        return manager.isCompleted(id: id) ? 1.0 : 0.0
    }
}
