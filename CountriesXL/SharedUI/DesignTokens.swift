import SwiftUI

public enum DesignTokens {
    public static let cornerRadius: CGFloat = 10
    public static let cardPadding: CGFloat = 12
    public static let smallSpacing: CGFloat = 8
    public static let mediumSpacing: CGFloat = 12
    public static let largeSpacing: CGFloat = 20

    public static var titleFont: Font { .system(.title2, design: .default).weight(.semibold) }
    public static var bodyFont: Font { .system(.body, design: .default) }
    public static var captionFont: Font { .system(.caption, design: .default) }

    // Symbol rendering mode used in the modernized UI
    public static var symbolRendering: SymbolRenderingMode { .hierarchical }
}
