// TourView.swift
// CountriesXL
import SwiftUI

struct TourStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let systemImage: String
}

struct TourView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.helpWindowCloser) private var helpWindowCloser

    @State private var index: Int = 0
    @State private var appear = false
    @State private var imageHover = false

    private let steps: [TourStep] = [
        TourStep(title: "Welcome", description: "Welcome to CountriesXL — a quick tour to get you started.", systemImage: "hand.wave.fill"),
        TourStep(title: "Explore Resources", description: "Browse and download resources from the Resources tab.", systemImage: "shippingbox.fill"),
        TourStep(title: "Use Downloads", description: "Manage downloads from the Downloads menu or toolbar.", systemImage: "arrow.down.circle.fill"),
        TourStep(title: "Stay Connected", description: "Sign in to access alerts, conversations, and profile features.", systemImage: "person.crop.circle.fill")
    ]

    private var current: TourStep { steps[index] }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(current.title).font(.system(.title3).weight(.semibold))
                    Text("Step \(index+1) of \(steps.count)")
                        .font(.caption)
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
                .accessibilityIdentifier("TourCloseButton")
            }
            .padding([.top, .horizontal])
            .accessibilityIdentifier("TourTitle")

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: current.systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(imageHover ? 1.06 : 1.0)
                    .onHover { hovering in withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { imageHover = hovering } }
                Text(current.description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 8)
            .animation(.easeOut(duration: 0.36), value: appear)

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation { index = max(0, index - 1) }
                }
                .disabled(index == 0)

                Spacer()

                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if index < steps.count - 1 {
                    Button("Next") {
                        withAnimation { index = min(steps.count - 1, index + 1) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("TourNextButton")
                } else {
                    Button("Finish") {
                        SettingsService.shared.update { model in
                            model.hasSeenTour = true
                        }
                        callHelpWindowCloser(helpWindowCloser, fallback: { dismiss() })
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("TourFinishButton")
                }
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 380)
        .padding()
        .opacity(appear ? 1 : 0)
        .scaleEffect(appear ? 1 : 0.995)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appear = true } }
        .onDisappear { appear = false }
    }
}

#Preview {
    TourView().environmentObject(AppState())
}
