import SwiftUI

// ElevationCard is defined centrally in SharedUI/ElevationCard.swift; use the shared modifier here.

struct GuideTopic: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

struct GuideView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.helpWindowCloser) private var helpWindowCloser

    @State private var query: String = ""
    @State private var appear = false

    private let topics: [GuideTopic] = [
        GuideTopic(title: "Getting Started", content: "Learn how to browse the app, sign in, and start downloading resources."),
        GuideTopic(title: "Managing Downloads", content: "Use the Downloads view to pause, resume, and cancel downloads. Use the clear button to remove completed items."),
        GuideTopic(title: "Account & Profile", content: "Sign in to access alerts, conversations, and your profile. Manage subscription from the Account menu."),
        GuideTopic(title: "Troubleshooting", content: "If the app cannot reach cities-mods.com, check your network connection and proxy settings in Preferences.")
    ]

    private var filtered: [GuideTopic] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return topics }
        return topics.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.content.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Guide")
                        .font(.system(.title2).weight(.semibold))
                    Text("Helpful topics and how-tos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .cancel) {
                    callHelpWindowCloser(helpWindowCloser, fallback: { dismiss() })
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityIdentifier("GuideCloseButton")
            }
            .padding([.top, .horizontal])
            .accessibilityIdentifier("GuideTitle")

            TextField("Search the guide", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { topic in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(topic.title)
                                    .font(.headline)
                                Text(topic.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .elevationCard()
                        .padding(.horizontal)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 6)
                        .animation(.easeOut(duration: 0.30).delay(Double(filtered.firstIndex(where: { $0.id == topic.id }) ?? 0) * 0.02), value: appear)
                    }
                }
                .padding(.vertical)
            }

            HStack {
                Spacer()
                Button("Done") {
                    callHelpWindowCloser(helpWindowCloser, fallback: { dismiss() })
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("GuideDoneButton")
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 420)
        .padding()
        .opacity(appear ? 1 : 0)
        .scaleEffect(appear ? 1 : 0.995)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appear = true } }
        .onDisappear { appear = false }
    }
}

#Preview {
    GuideView().environmentObject(AppState())
}
