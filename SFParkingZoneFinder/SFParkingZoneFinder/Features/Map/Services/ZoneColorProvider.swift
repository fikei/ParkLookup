import SwiftUI
import UIKit

/// Provides consistent colors for parking zone visualization on maps
enum ZoneColorProvider {

    // MARK: - Zone Colors

    /// Get the color for a zone by its permit area code
    /// Uses a curated palette designed for visual differentiation
    static func color(for zoneCode: String?) -> UIColor {
        guard let code = zoneCode?.uppercased() else {
            return .systemGray
        }

        // Map zone codes to palette colors
        // SF has zones A-Z plus AA, BB, CC, etc.
        return zoneColors[code] ?? colorFromHash(code)
    }

    /// SwiftUI Color wrapper
    static func swiftUIColor(for zoneCode: String?) -> Color {
        Color(uiColor: color(for: zoneCode))
    }

    // MARK: - Curated Color Palette

    /// Hand-picked colors for SF RPP zones
    /// Designed for good visual separation and accessibility
    private static let zoneColors: [String: UIColor] = [
        // Primary zones (A-L) - warm to cool spectrum
        "A": UIColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1.0),  // Red
        "B": UIColor(red: 0.95, green: 0.50, blue: 0.20, alpha: 1.0),  // Orange
        "C": UIColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 1.0),  // Gold
        "D": UIColor(red: 0.75, green: 0.80, blue: 0.20, alpha: 1.0),  // Lime
        "E": UIColor(red: 0.30, green: 0.75, blue: 0.40, alpha: 1.0),  // Green
        "F": UIColor(red: 0.20, green: 0.70, blue: 0.60, alpha: 1.0),  // Teal
        "G": UIColor(red: 0.20, green: 0.60, blue: 0.80, alpha: 1.0),  // Sky Blue
        "H": UIColor(red: 0.30, green: 0.45, blue: 0.85, alpha: 1.0),  // Blue
        "I": UIColor(red: 0.50, green: 0.35, blue: 0.80, alpha: 1.0),  // Indigo
        "J": UIColor(red: 0.70, green: 0.35, blue: 0.75, alpha: 1.0),  // Purple
        "K": UIColor(red: 0.85, green: 0.35, blue: 0.60, alpha: 1.0),  // Pink
        "L": UIColor(red: 0.80, green: 0.40, blue: 0.40, alpha: 1.0),  // Rose

        // Secondary zones (M-X) - varied hues
        "M": UIColor(red: 0.60, green: 0.45, blue: 0.35, alpha: 1.0),  // Brown
        "N": UIColor(red: 0.45, green: 0.55, blue: 0.45, alpha: 1.0),  // Sage
        "O": UIColor(red: 0.55, green: 0.65, blue: 0.75, alpha: 1.0),  // Steel
        "P": UIColor(red: 0.75, green: 0.55, blue: 0.65, alpha: 1.0),  // Mauve
        "Q": UIColor(red: 0.40, green: 0.65, blue: 0.55, alpha: 1.0),  // Sea Green
        "R": UIColor(red: 0.85, green: 0.55, blue: 0.35, alpha: 1.0),  // Coral
        "S": UIColor(red: 0.55, green: 0.50, blue: 0.70, alpha: 1.0),  // Lavender
        "T": UIColor(red: 0.65, green: 0.75, blue: 0.45, alpha: 1.0),  // Olive
        "U": UIColor(red: 0.50, green: 0.70, blue: 0.80, alpha: 1.0),  // Cyan
        "V": UIColor(red: 0.80, green: 0.45, blue: 0.55, alpha: 1.0),  // Raspberry
        "W": UIColor(red: 0.45, green: 0.60, blue: 0.70, alpha: 1.0),  // Slate
        "X": UIColor(red: 0.70, green: 0.60, blue: 0.50, alpha: 1.0),  // Tan
        "Y": UIColor(red: 0.85, green: 0.75, blue: 0.35, alpha: 1.0),  // Yellow
        "Z": UIColor(red: 0.55, green: 0.45, blue: 0.60, alpha: 1.0),  // Plum

        // Double-letter zones (AA, BB, etc.)
        "AA": UIColor(red: 0.75, green: 0.25, blue: 0.25, alpha: 1.0),
        "BB": UIColor(red: 0.80, green: 0.45, blue: 0.15, alpha: 1.0),
        "CC": UIColor(red: 0.25, green: 0.65, blue: 0.35, alpha: 1.0),
        "DD": UIColor(red: 0.25, green: 0.50, blue: 0.70, alpha: 1.0),
        "EE": UIColor(red: 0.60, green: 0.30, blue: 0.65, alpha: 1.0),
        "FF": UIColor(red: 0.70, green: 0.30, blue: 0.45, alpha: 1.0),
        "GG": UIColor(red: 0.50, green: 0.60, blue: 0.35, alpha: 1.0),
        "HH": UIColor(red: 0.35, green: 0.55, blue: 0.65, alpha: 1.0),
        "II": UIColor(red: 0.65, green: 0.50, blue: 0.60, alpha: 1.0),
        "JJ": UIColor(red: 0.55, green: 0.70, blue: 0.55, alpha: 1.0),
        "KK": UIColor(red: 0.70, green: 0.55, blue: 0.40, alpha: 1.0),
        "LL": UIColor(red: 0.45, green: 0.45, blue: 0.65, alpha: 1.0),
    ]

    /// Fallback: generate color from zone code hash for unknown zones
    private static func colorFromHash(_ code: String) -> UIColor {
        let hash = abs(code.hashValue)
        let hue = CGFloat(hash % 360) / 360.0
        let saturation: CGFloat = 0.5 + CGFloat((hash / 360) % 30) / 100.0
        let brightness: CGFloat = 0.6 + CGFloat((hash / 10800) % 20) / 100.0
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    }

    // MARK: - Overlay Styling

    /// Fill color for zone polygon overlay (semi-transparent)
    static func fillColor(for zoneCode: String?, isCurrentZone: Bool) -> UIColor {
        let baseColor = color(for: zoneCode)
        let alpha: CGFloat = isCurrentZone ? 0.35 : 0.20
        return baseColor.withAlphaComponent(alpha)
    }

    /// Stroke color for zone polygon border
    static func strokeColor(for zoneCode: String?, isCurrentZone: Bool) -> UIColor {
        let baseColor = color(for: zoneCode)
        let alpha: CGFloat = isCurrentZone ? 1.0 : 0.6
        return baseColor.withAlphaComponent(alpha)
    }

    /// Stroke width for zone polygon border
    static func strokeWidth(isCurrentZone: Bool) -> CGFloat {
        isCurrentZone ? 3.0 : 1.5
    }
}
