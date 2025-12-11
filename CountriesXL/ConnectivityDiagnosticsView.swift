import SwiftUI

struct ConnectivityDiagnosticsView: View {
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var board = BoardStatusService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Network")) {
                    LabeledContent("Connected") { Text(boolText(network.isConnected)) }
                    LabeledContent("Domain Reachable") { Text(boolText(network.domainReachable)) }
                    if let last = network.lastChecked {
                        LabeledContent("Last Checked") { Text(last.formatted(date: .abbreviated, time: .standard)) }
                    }
                    if let err = network.lastError, !err.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Error Detail").font(.subheadline).foregroundStyle(.secondary)
                            ScrollView { Text(err).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                .frame(maxHeight: 140)
                                .padding(8)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    HStack(spacing: 12) {
                        Button("Re-check Network") { Task { await network.checkNow() } }
                        Button("Copy Error") { copy(network.lastError) }.disabled((network.lastError ?? "").isEmpty)
                    }
                }
                Section(header: Text("Board")) {
                    LabeledContent("Active") { Text(board.isActive ? "Yes" : "No") }
                    if !board.versionString.isEmpty {
                        LabeledContent("Version") { Text(board.versionString) }
                    }
                    LabeledContent("XF 2.3+") { Text(board.isXF23OrNewer ? "Yes" : "No") }
                    if let last = board.lastChecked {
                        LabeledContent("Last Checked") { Text(last.formatted(date: .abbreviated, time: .standard)) }
                    }
                    if let err = board.lastError, !err.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Error Detail").font(.subheadline).foregroundStyle(.secondary)
                            ScrollView { Text(err).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                .frame(maxHeight: 140)
                                .padding(8)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    HStack(spacing: 12) {
                        Button("Re-check Board") { Task { await board.refresh() } }
                        Button("Copy Error") { copy(board.lastError) }.disabled((board.lastError ?? "").isEmpty)
                    }
                }
            }
            .navigationTitle("Connectivity Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func boolText(_ value: Bool?) -> String {
        guard let v = value else { return "Unknown" }
        return v ? "Yes" : "No"
    }

    private func copy(_ text: String?) {
        #if os(macOS)
        if let s = text { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
        #endif
    }
}

#Preview {
    ConnectivityDiagnosticsView()
}
