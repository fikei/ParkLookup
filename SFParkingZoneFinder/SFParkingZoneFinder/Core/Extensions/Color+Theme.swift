import SwiftUI

// MARK: - App Theme Colors

extension Color {
    // MARK: - Validity Status Colors

    /// Green - permit is valid
    static let validGreen = Color("ValidGreen", bundle: nil)

    /// Red - permit is not valid
    static let invalidRed = Color("InvalidRed", bundle: nil)

    /// Yellow - conditional validity
    static let conditionalYellow = Color("ConditionalYellow", bundle: nil)

    /// Gray - no permit required
    static let noPermitGray = Color("NoPermitGray", bundle: nil)

    /// Blue - multiple permits apply
    static let multipleBlue = Color("MultipleBlue", bundle: nil)

    // MARK: - Fallback Colors (when asset catalog not configured)

    static var validGreenFallback: Color { Color.green }
    static var invalidRedFallback: Color { Color.red }
    static var conditionalYellowFallback: Color { Color.yellow }
    static var noPermitGrayFallback: Color { Color.gray }
    static var multipleBlueFallback: Color { Color.blue }

    // MARK: - Status Color Helper

    static func forValidityStatus(_ status: PermitValidityStatus) -> Color {
        switch status {
        case .valid:
            return .green
        case .invalid:
            return .red
        case .conditional:
            return .yellow
        case .noPermitRequired:
            return .gray
        case .multipleApply:
            return .blue
        case .noPermitSet:
            return .orange
        }
    }

    // MARK: - Zone Type Colors

    static func forZoneType(_ type: ZoneType) -> Color {
        switch type {
        case .residentialPermit:
            return .blue
        case .metered:
            return .green
        case .timeLimited:
            return .orange
        case .noParking:
            return .red
        case .towAway:
            return .red
        case .mixed:
            return .purple
        }
    }

    // MARK: - Map Zone Colors

    static func zonePolygonFill(for type: ZoneType) -> Color {
        forZoneType(type).opacity(0.2)
    }

    static func zonePolygonStroke(for type: ZoneType) -> Color {
        forZoneType(type)
    }
}

// MARK: - UIColor Extension

import UIKit

extension UIColor {
    static func forValidityStatus(_ status: PermitValidityStatus) -> UIColor {
        switch status {
        case .valid:
            return .systemGreen
        case .invalid:
            return .systemRed
        case .conditional:
            return .systemYellow
        case .noPermitRequired:
            return .systemGray
        case .multipleApply:
            return .systemBlue
        case .noPermitSet:
            return .systemOrange
        }
    }

    static func forZoneType(_ type: ZoneType) -> UIColor {
        switch type {
        case .residentialPermit:
            return .systemBlue
        case .metered:
            return .systemGreen
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
}
