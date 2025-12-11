import SwiftUI

/// Shared elevation card modifier used across help dialogs (WhatsNew, Guide, Tour).
/// Provides hover elevation and subtle shadow consistent with macOS 26 motifs.
public struct ElevationCardModifier: ViewModifier {
    @State private var hovered = false

    public init() {}

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .scaleEffect(hovered ? 1.01 : 1.0)
            .shadow(color: Color.black.opacity(hovered ? 0.18 : 0.06), radius: hovered ? 10 : 4, x: 0, y: hovered ? 6 : 2)
            .onHover { hovering in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { hovered = hovering }
            }
    }
}

public extension View {
    func elevationCard() -> some View {
        modifier(ElevationCardModifier())
    }
}
