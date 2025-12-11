import SwiftUI

struct DownloadsView: View {
    @State private var items: [DownloadManager.Item] = []
    @AppStorage("downloadProgressDisplay") private var downloadProgressDisplay: String = "bytes"
    @AppStorage("downloadShowRate") private var downloadShowRate: Bool = true

    var body: some View {
        VStack(alignment: .leading) {
            List(items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.filename).font(.headline)
                        if let local = item.localFileURL {
                            Text(local.path).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if item.completed {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Button("Clear") {
                                Task { await DownloadManager.shared.clear(url: item.url) }
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if let error = item.errorDescription, !error.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            Text(error).foregroundStyle(.secondary)
                            Button("Clear") {
                                Task { await DownloadManager.shared.clear(url: item.url) }
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if item.paused {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) {
                                ProgressView(value: item.progress).frame(width: 160)
                                Text("\(Int(item.progress * 100))%")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Button("Resume") {
                                    Task { await DownloadManager.shared.resume(url: item.url) }
                                }
                                Button("Cancel") {
                                    Task { await DownloadManager.shared.cancel(url: item.url) }
                                }
                            }
                            if downloadProgressDisplay == "eta" {
                                if let info = etaInfo(for: item) {
                                    Text(info)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                if let info = bytesInfo(for: item) {
                                    Text(info)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    } else if item.isDownloading {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) {
                                ProgressView(value: item.progress).frame(width: 160)
                                Text("\(Int(item.progress * 100))%")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Button("Pause") {
                                    Task { await DownloadManager.shared.pause(url: item.url) }
                                }
                                Button("Cancel") {
                                    Task { await DownloadManager.shared.cancel(url: item.url) }
                                }
                            }
                            if downloadProgressDisplay == "eta" {
                                if let info = etaInfo(for: item) {
                                    Text(info)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                if let info = bytesInfo(for: item) {
                                    Text(info)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView(value: item.progress).frame(width: 160)
                            Text("\(Int(item.progress * 100))%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("Files saved to ~/Downloads/CountriesXL").font(.footnote).foregroundStyle(.secondary).padding([.leading, .bottom])
            }
        }
        .navigationTitle("Downloads")
        .task(id: UUID()) { await pollDownloads() }
    }

    private func pollDownloads() async {
        // simple polling to reflect actor state changes
        while true {
            let snapshot = await DownloadManager.shared.items
            await MainActor.run { self.items = snapshot }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    private func bytesInfo(for item: DownloadManager.Item) -> String? {
        // Format "x MB of y MB (ETA mm:ss)" when possible
        let written = item.totalBytesWritten
        let expected = item.totalBytesExpected
        let writtenText = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
        if let exp = expected, exp > 0 {
            let totalText = ByteCountFormatter.string(fromByteCount: exp, countStyle: .file)
            var parts = ["\(writtenText) of \(totalText)"]
            if let eta = estimateETA(written: written, total: exp, startedAt: item.startedAt) {
                parts.append("ETA \(eta)")
            }
            return parts.joined(separator: "  ")
        } else {
            return written > 0 ? writtenText : nil
        }
    }

    private func etaInfo(for item: DownloadManager.Item) -> String? {
        let written = item.totalBytesWritten
        let expected = item.totalBytesExpected
        if let exp = expected, exp > 0, let eta = estimateETA(written: written, total: exp, startedAt: item.startedAt) {
            var parts: [String] = ["ETA \(eta)"]
            if downloadShowRate, let started = item.startedAt {
                let elapsed = Date().timeIntervalSince(started)
                if elapsed > 0 {
                    let rate = Double(written) / elapsed // bytes per second
                    if rate > 0 {
                        parts.append(formatRate(rate))
                    }
                }
            }
            return parts.joined(separator: " • ")
        }
        return nil
    }

    private func formatRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        let value = formatter.string(fromByteCount: Int64(bytesPerSecond))
        return "\(value)/s"
    }

    private func estimateETA(written: Int64, total: Int64, startedAt: Date?) -> String? {
        guard total > 0, written > 0, let startedAt else { return nil }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0 else { return nil }
        let rate = Double(written) / elapsed // bytes per second
        guard rate > 0 else { return nil }
        let remaining = Double(total - written) / rate
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

