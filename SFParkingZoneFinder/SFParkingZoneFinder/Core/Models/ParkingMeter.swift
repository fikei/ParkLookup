import Foundation
import CoreLocation

/// Represents a single parking meter location
struct ParkingMeter: Codable, Identifiable, Hashable {
    let id: String
    let postId: String
    let streetName: String?
    let streetNum: String?
    let geometry: PointGeometry
    let activeMeterFlag: String?
    let meterType: String?
    let meterVendor: String?
    let meterModel: String?
    let capColor: String?
    let blockfaceId: String?
    let pmDistrictId: String?

    enum CodingKeys: String, CodingKey {
        case id = ":id"
        case postId = "post_id"
        case streetName = "street_name"
        case streetNum = "street_num"
        case geometry
        case activeMeterFlag = "active_meter_flag"
        case meterType = "meter_type"
        case meterVendor = "meter_vendor"
        case meterModel = "meter_model"
        case capColor = "cap_color"
        case blockfaceId = "blockface_id"
        case pmDistrictId = "pm_district_id"
    }

    /// Display name for this meter
    var displayName: String {
        var parts: [String] = []

        if let street = streetName {
            parts.append(street)
        }
        if let num = streetNum {
            parts.append(num)
        }

        if parts.isEmpty {
            return "Meter \(postId)"
        }

        return parts.joined(separator: " ")
    }

    /// Coordinate for this meter
    var coordinate: CLLocationCoordinate2D {
        geometry.locationCoordinate
    }

    /// Whether this meter is active
    var isActive: Bool {
        activeMeterFlag == "M" || activeMeterFlag == "P"
    }

    /// Status description
    var statusDescription: String {
        switch activeMeterFlag {
        case "M": return "Active (Metered)"
        case "P": return "Active (Pay Station)"
        case "T": return "Temporarily Inactive"
        case "U": return "Inactive"
        default: return "Unknown"
        }
    }
}

/// Point geometry for meter location
struct PointGeometry: Codable, Hashable {
    let type: String  // Always "Point"
    let coordinates: [Double]  // [lon, lat]

    /// Convert to CLLocationCoordinate2D for MapKit
    var locationCoordinate: CLLocationCoordinate2D {
        guard coordinates.count >= 2 else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        return CLLocationCoordinate2D(
            latitude: coordinates[1],   // GeoJSON is [lon, lat]
            longitude: coordinates[0]
        )
    }
}
