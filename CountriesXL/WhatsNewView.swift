import SwiftUI

struct WhatsNewItem: Identifiable {
    let id = UUID()
    let title: String
    let details: String
    let systemImage: String?
}

struct WhatsNewView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.helpWindowCloser) private var helpWindowCloser

    @State private var appear = false

    private let items: [WhatsNewItem] = [
        WhatsNewItem(title: "Refreshed UI", details: "Help dialogs and sheets received a visual refresh for a cleaner, more modern look.", systemImage: "sparkles"),
        WhatsNewItem(title: "Improved Downloads", details: "Downloads are more reliable and offer better progress feedback.", systemImage: "arrow.down.circle.fill"),
        WhatsNewItem(title: "Privacy & Settings", details: "New settings make it easier to control telemetry and appearance.", systemImage: "shield.lefthalf.filled"),
        WhatsNewItem(title: "Bug fixes", details: "Various stability and layout fixes across the app.", systemImage: "wrench.fill")
    ]

    var body: some View {
        ZStack {
            // subtle backdrop to let the sheet chrome breathe
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.9)

            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What's New")
                            .font(DesignTokens.titleFont)
                        Text("Highlights from recent updates")
                            .font(DesignTokens.captionFont)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .cancel) {
                        if let close = helpWindowCloser { close() } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                    .accessibilityIdentifier("WhatsNewCloseButton")
                }
                .padding([.top, .horizontal])

                Divider()

                ScrollView {
                    LazyVStack(spacing: 14, pinnedViews: []) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                if let icon = item.systemImage {
                                    Image(systemName: icon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 34, height: 34)
                                        .symbolRenderingMode(DesignTokens.symbolRendering)
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.top, 4)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(DesignTokens.bodyFont.weight(.semibold))
                                    Text(item.details)
                                        .font(DesignTokens.bodyFont)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .elevationCard()
                            .padding(.horizontal)
                            // subtle entrance animation
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 8)
                            .animation(.easeOut(duration: 0.35).delay(Double(items.firstIndex(where: { $0.id == item.id }) ?? 0) * 0.03), value: appear)
                        }
                    }
                    .padding(.vertical)
                }

                HStack {
                    Spacer()
                    Button("Dismiss") {
                        if let close = helpWindowCloser { close() } else { dismiss() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("WhatsNewDismissButton")
                }
                .padding()
            }
            .frame(minWidth: 520, minHeight: 420)
            .padding()
            .opacity(appear ? 1 : 0)
            .scaleEffect(appear ? 1 : 0.995)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appear = true }
        }
        .onDisappear {
            appear = false
        }
    }
}

#Preview {
    WhatsNewView().environmentObject(AppState())
}
