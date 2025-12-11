import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
#endif

public struct CodableColor: Codable, Equatable, Hashable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ color: Color) {
        #if canImport(UIKit)
        let ui = PlatformColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, &g, &b, &a)
        #elseif canImport(AppKit)
        let ns = PlatformColor(color)
        let converted = ns.usingColorSpace(.deviceRGB) ?? ns
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        self.red = r
        self.green = g
        self.blue = b
        self.alpha = a
    }

    public var color: Color {
        #if canImport(UIKit)
        return Color(PlatformColor(red: red, green: green, blue: blue, alpha: alpha))
        #elseif canImport(AppKit)
        return Color(PlatformColor(calibratedRed: red, green: green, blue: blue, alpha: alpha))
        #else
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
        #endif
    }

    // Codable
    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        red = try c.decode(CGFloat.self, forKey: .red)
        green = try c.decode(CGFloat.self, forKey: .green)
        blue = try c.decode(CGFloat.self, forKey: .blue)
        alpha = try c.decode(CGFloat.self, forKey: .alpha)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(red, forKey: .red)
        try c.encode(green, forKey: .green)
        try c.encode(blue, forKey: .blue)
        try c.encode(alpha, forKey: .alpha)
    }
}
