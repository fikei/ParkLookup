import SwiftUI
import UIKit

/// Provides consistent colors for parking zone visualization on maps
enum ZoneColorProvider {

    // MARK: - Standard Colors

    /// Color for user's valid permit zone (green)
    static let userZoneColor = UIColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1.0)  // #33B366 Green

    /// Color for all other RPP zones (orange)
    static let rppZoneColor = UIColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1.0)  // #F29933 Orange

    /// Color for metered/paid parking zones (grey)
    static let meteredZoneColor = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)  // #808080 Grey

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

    /// Get the color for a zone by its type
    static func color(for zoneType: ZoneType) -> UIColor {
        switch zoneType {
        case .metered:
            return meteredZoneColor
        case .residentialPermit:
            return rppZoneColor  // Default orange for RPP
        case .timeLimited:
            return .systemOrange
        case .noParking:
            return .systemRed
        case .towAway:
            return .systemRed
        case .mixed:
            return .systemPurple
        }
    }

    /// Get the color for a zone considering user's valid permit areas
    /// - Parameters:
    ///   - zone: The parking zone to color
    ///   - userPermitAreas: Set of permit area codes the user has valid permits for
    /// - Returns: Green for user's zones, grey for metered, orange for other RPP
    static func color(for zone: ParkingZone, userPermitAreas: Set<String>) -> UIColor {
        // Metered zones are always grey
        if zone.zoneType == .metered {
            return meteredZoneColor
        }

        // Check if this is user's valid permit zone
        if let permitArea = zone.permitArea?.uppercased(),
           userPermitAreas.contains(permitArea) {
            return userZoneColor
        }

        // All other RPP zones are orange
        if zone.zoneType == .residentialPermit {
            return rppZoneColor
        }

        // Fallback to type-based coloring
        return color(for: zone.zoneType)
    }

    /// SwiftUI Color wrapper
    static func swiftUIColor(for zoneCode: String?) -> Color {
        Color(uiColor: color(for: zoneCode))
    }

    /// SwiftUI Color wrapper for zone type
    static func swiftUIColor(for zoneType: ZoneType) -> Color {
        Color(uiColor: color(for: zoneType))
    }

    // MARK: - Curated Color Palette

    /// Hand-picked colors for SF RPP zones
    /// Designed for good visual separation and accessibility
    private static let zoneColors: [String: UIColor] = [
        // Primary zones (A-L)
        "A": UIColor(red: 0.502, green: 0.349, blue: 0.800, alpha: 1.0),  // #8059CC Indigo
        "B": UIColor(red: 0.949, green: 0.502, blue: 0.200, alpha: 1.0),  // #F28033 Orange
        "C": UIColor(red: 0.949, green: 0.702, blue: 0.200, alpha: 1.0),  // #F2B333 Gold
        "D": UIColor(red: 0.749, green: 0.800, blue: 0.200, alpha: 1.0),  // #BFCC33 Lime
        "E": UIColor(red: 0.302, green: 0.749, blue: 0.400, alpha: 1.0),  // #4DBF66 Green
        "F": UIColor(red: 0.200, green: 0.702, blue: 0.600, alpha: 1.0),  // #33B399 Teal
        "G": UIColor(red: 0.200, green: 0.600, blue: 0.800, alpha: 1.0),  // #3399CC Sky Blue
        "H": UIColor(red: 0.549, green: 0.502, blue: 0.702, alpha: 1.0),  // #8C80B3 Lavender
        "I": UIColor(red: 0.902, green: 0.302, blue: 0.302, alpha: 1.0),  // #E64D4D Red
        "J": UIColor(red: 0.702, green: 0.349, blue: 0.749, alpha: 1.0),  // #B359BF Purple
        "K": UIColor(red: 0.851, green: 0.349, blue: 0.600, alpha: 1.0),  // #D95999 Pink
        "L": UIColor(red: 0.800, green: 0.400, blue: 0.400, alpha: 1.0),  // #CC6666 Rose

        // Secondary zones (M-Z)
        "M": UIColor(red: 0.600, green: 0.451, blue: 0.349, alpha: 1.0),  // #997359 Brown
        "N": UIColor(red: 0.451, green: 0.549, blue: 0.451, alpha: 1.0),  // #738C73 Sage
        "O": UIColor(red: 0.549, green: 0.651, blue: 0.749, alpha: 1.0),  // #8CA6BF Steel
        "P": UIColor(red: 0.749, green: 0.549, blue: 0.651, alpha: 1.0),  // #BF8CA6 Mauve
        "Q": UIColor(red: 0.400, green: 0.651, blue: 0.549, alpha: 1.0),  // #66A68C Sea Green
        "R": UIColor(red: 0.851, green: 0.549, blue: 0.349, alpha: 1.0),  // #D98C59 Coral
        "S": UIColor(red: 0.302, green: 0.451, blue: 0.851, alpha: 1.0),  // #4D73D9 Blue
        "T": UIColor(red: 0.651, green: 0.749, blue: 0.451, alpha: 1.0),  // #A6BF73 Olive
        "U": UIColor(red: 0.502, green: 0.702, blue: 0.800, alpha: 1.0),  // #80B3CC Cyan
        "V": UIColor(red: 0.800, green: 0.451, blue: 0.549, alpha: 1.0),  // #CC738C Raspberry
        "W": UIColor(red: 0.451, green: 0.600, blue: 0.702, alpha: 1.0),  // #7399B3 Slate
        "X": UIColor(red: 0.702, green: 0.600, blue: 0.502, alpha: 1.0),  // #B39980 Tan
        "Y": UIColor(red: 0.851, green: 0.749, blue: 0.349, alpha: 1.0),  // #D9BF59 Yellow
        "Z": UIColor(red: 0.549, green: 0.451, blue: 0.651, alpha: 1.0),  // #8C73A6 Plum

        // Double-letter zones (AA, BB, etc.)
        "AA": UIColor(red: 0.749, green: 0.251, blue: 0.251, alpha: 1.0),  // #BF4040 Dark Red
        "BB": UIColor(red: 0.800, green: 0.451, blue: 0.149, alpha: 1.0),  // #CC7326 Burnt Orange
        "CC": UIColor(red: 0.251, green: 0.651, blue: 0.349, alpha: 1.0),  // #40A659 Forest Green
        "DD": UIColor(red: 0.251, green: 0.502, blue: 0.702, alpha: 1.0),  // #4080B3 Navy
        "EE": UIColor(red: 0.600, green: 0.302, blue: 0.651, alpha: 1.0),  // #994DA6 Violet
        "FF": UIColor(red: 0.702, green: 0.302, blue: 0.451, alpha: 1.0),  // #B34D73 Magenta
        "GG": UIColor(red: 0.502, green: 0.600, blue: 0.349, alpha: 1.0),  // #809959 Moss
        "HH": UIColor(red: 0.349, green: 0.549, blue: 0.651, alpha: 1.0),  // #598CA6 Teal Blue
        "II": UIColor(red: 0.651, green: 0.502, blue: 0.600, alpha: 1.0),  // #A68099 Dusty Rose
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

    /// Fill color for zone polygon overlay by zone type
    static func fillColor(for zoneType: ZoneType, isCurrentZone: Bool) -> UIColor {
        let baseColor = color(for: zoneType)
        let alpha: CGFloat = isCurrentZone ? 0.35 : 0.20
        return baseColor.withAlphaComponent(alpha)
    }

    /// Stroke color for zone polygon border
    static func strokeColor(for zoneCode: String?, isCurrentZone: Bool) -> UIColor {
        let baseColor = color(for: zoneCode)
        let alpha: CGFloat = isCurrentZone ? 1.0 : 0.6
        return baseColor.withAlphaComponent(alpha)
    }

    /// Stroke color for zone polygon border by zone type
    static func strokeColor(for zoneType: ZoneType, isCurrentZone: Bool) -> UIColor {
        let baseColor = color(for: zoneType)
        let alpha: CGFloat = isCurrentZone ? 1.0 : 0.6
        return baseColor.withAlphaComponent(alpha)
    }

    /// Stroke width for zone polygon border (reduced for less prominence)
    static func strokeWidth(isCurrentZone: Bool) -> CGFloat {
        isCurrentZone ? 2.0 : 1.0
    }

    /// Get color for a ParkingZone (uses zone type for metered, permit area for RPP)
    static func color(for zone: ParkingZone) -> UIColor {
        if zone.zoneType == .metered {
            return meteredZoneColor
        }
        return color(for: zone.permitArea)
    }

    /// Fill color for a ParkingZone
    static func fillColor(for zone: ParkingZone, isCurrentZone: Bool) -> UIColor {
        let baseColor = color(for: zone)
        let alpha: CGFloat = isCurrentZone ? 0.35 : 0.20
        return baseColor.withAlphaComponent(alpha)
    }

    /// Stroke color for a ParkingZone
    static func strokeColor(for zone: ParkingZone, isCurrentZone: Bool) -> UIColor {
        let baseColor = color(for: zone)
        let alpha: CGFloat = isCurrentZone ? 1.0 : 0.6
        return baseColor.withAlphaComponent(alpha)
    }

    // MARK: - User Permit-Aware Coloring

    /// Fill color for a zone considering user's valid permit areas
    static func fillColor(for zone: ParkingZone, userPermitAreas: Set<String>, isCurrentZone: Bool) -> UIColor {
        let baseColor = color(for: zone, userPermitAreas: userPermitAreas)
        let alpha: CGFloat = isCurrentZone ? 0.35 : 0.20
        return baseColor.withAlphaComponent(alpha)
    }

    /// Stroke color for a zone considering user's valid permit areas
    static func strokeColor(for zone: ParkingZone, userPermitAreas: Set<String>, isCurrentZone: Bool) -> UIColor {
        let baseColor = color(for: zone, userPermitAreas: userPermitAreas)
        let alpha: CGFloat = isCurrentZone ? 1.0 : 0.6
        return baseColor.withAlphaComponent(alpha)
    }

    /// SwiftUI Color for zone with user permit awareness
    static func swiftUIColor(for zone: ParkingZone, userPermitAreas: Set<String>) -> Color {
        Color(uiColor: color(for: zone, userPermitAreas: userPermitAreas))
    }
}
