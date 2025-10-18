import SwiftUI

struct DisconnectedOverlayView: View {
    let title: String
    let message: String
    let details: String?
    let primaryActionTitle: String
    let primaryAction: () -> Void
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?
    let brandingImage: Image?
    let tertiaryActionTitle: String?
    let tertiaryAction: (() -> Void)?
    let brandingSize: CGFloat?
    let brandingPlate: Bool

    // Customization knobs (non-breaking: all have defaults)
    var cardCornerRadius: CGFloat = 20
    var plateCornerRadius: CGFloat = 18
    var maxCardWidth: CGFloat = 560

    enum ButtonStyleChoice { case bordered, borderedProminent, plain, link }
    var primaryStyle: ButtonStyleChoice = .borderedProminent
    var secondaryStyle: ButtonStyleChoice = .bordered
    var tertiaryStyle: ButtonStyleChoice = .plain

    // Backdrop opacities for light/dark modes
    var lightBackdropOpacity: Double = 0.75
    var darkBackdropOpacity: Double = 0.55

    @State private var revealDetails: Bool = false

    var body: some View {
        ZStack {
            // Soft gradient + blur background instead of solid black
            overlayBackground
                .ignoresSafeArea()

            // Card
            VStack(spacing: 18) {
                if let brandingImage = brandingImage {
                    let size = brandingSize ?? 120
                    brandingImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .if(brandingPlate) { view in
                            view
                                .padding(6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .accessibilityHidden(true)
                }

                Image(systemName: "wifi.exclamationmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title2).bold()
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                if let details = details, !details.isEmpty {
                    DisclosureGroup(isExpanded: $revealDetails) {
                        ScrollView {
                            Text(details)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 140)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.06))
                        )
                    } label: {
                        Text("Details")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                // Actions
                HStack(spacing: 12) {
                    if let secondary = secondaryAction, let secondaryTitle = secondaryActionTitle {
                        Button(secondaryTitle) { secondary() }
                            .applyButtonStyle(secondaryStyle)
                    }
                    if let tertiary = tertiaryAction, let tertiaryTitle = tertiaryActionTitle {
                        Button(tertiaryTitle) { tertiary() }
                            .applyButtonStyle(tertiaryStyle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(primaryActionTitle) { primaryAction() }
                        .applyButtonStyle(primaryStyle)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .padding(20)
            .frame(maxWidth: maxCardWidth)
            .background(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(overlayStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 8)
            .padding(24)
            .transition(.scale.combined(with: .opacity))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(message)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {}
        }
    }

    // MARK: - Visual helpers

    @Environment(\.colorScheme) private var colorScheme

    private var overlayBackground: some View {
        let base = colorScheme == .dark ? Color.black : Color.white
        let opacity = colorScheme == .dark ? darkBackdropOpacity : lightBackdropOpacity
        return base.opacity(opacity)
    }

    private var overlayStroke: LinearGradient {
        let start = Color.white.opacity(colorScheme == .dark ? 0.18 : 0.22)
        let end = Color.black.opacity(colorScheme == .dark ? 0.25 : 0.12)
        return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

private extension View {
    @ViewBuilder
    func applyButtonStyle(_ style: DisconnectedOverlayView.ButtonStyleChoice) -> some View {
        switch style {
        case .bordered:
            self.buttonStyle(.bordered)
        case .borderedProminent:
            self.buttonStyle(.borderedProminent)
        case .plain:
            self.buttonStyle(.plain)
        case .link:
            #if os(macOS)
            self.buttonStyle(.link)
            #else
            self.buttonStyle(.plain)
            #endif
        }
    }
}

#Preview {
    DisconnectedOverlayView(
        title: "No Internet",
        message: "This app requires access to cities-mods.com.",
        details: "Network timeout after 3s\nReachability probe to https://cities-mods.com failed.",
        primaryActionTitle: "Try Again",
        primaryAction: {},
        secondaryActionTitle: "Close",
        secondaryAction: {},
        brandingImage: Image(systemName: "globe"),
        tertiaryActionTitle: "Diagnostics…",
        tertiaryAction: {},
        brandingSize: 140,
        brandingPlate: true,
        cardCornerRadius: 24,
        plateCornerRadius: 20,
        maxCardWidth: 600,
        primaryStyle: .borderedProminent,
        secondaryStyle: .bordered,
        tertiaryStyle: .link
    )
}

