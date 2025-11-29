import Foundation
import CoreLocation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ParkingMeterLoader")

// MARK: - ParkingMeter Model

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

// MARK: - ParkingMeterLoader

/// Loads parking meter data from external GeoJSON file
class ParkingMeterLoader {
    static let shared = ParkingMeterLoader()

    private var cachedMeters: [ParkingMeter]?

    private init() {}

    /// Load parking meters from external GeoJSON file
    func loadParkingMeters() throws -> [ParkingMeter] {
        if let cached = cachedMeters {
            logger.info("Returning cached parking meters")
            return cached
        }

        logger.info("Loading parking meters from external GeoJSON")

        // Path to the external dataset
        let fileURL = URL(fileURLWithPath: "/home/user/ParkLookup/Data Sets/Parking_Meters_20251128.geojson")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("Parking_Meters_20251128.geojson not found at path: \(fileURL.path)")
            throw ParkingMeterLoaderError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)

        // Decode GeoJSON
        let response = try JSONDecoder().decode(ParkingMeterGeoJSON.self, from: data)

        // Convert features to ParkingMeter models
        let meters = response.features.compactMap { $0.toParkingMeter() }

        cachedMeters = meters

        logger.info("Loaded \(meters.count) parking meters")

        return meters
    }

    /// Get active parking meters only
    func getActiveMeters() throws -> [ParkingMeter] {
        let meters = try loadParkingMeters()
        return meters.filter { $0.isActive }
    }

    /// Clear cache to reload data
    func clearCache() {
        cachedMeters = nil
        logger.info("Cleared parking meter cache")
    }
}

/// GeoJSON FeatureCollection wrapper
struct ParkingMeterGeoJSON: Codable {
    let type: String
    let features: [ParkingMeterFeature]
}

/// GeoJSON Feature wrapper for parking meter
struct ParkingMeterFeature: Codable {
    let type: String
    let geometry: PointGeometry
    let properties: ParkingMeterProperties

    /// Convert to ParkingMeter model
    func toParkingMeter() -> ParkingMeter? {
        guard let id = properties.id else { return nil }

        return ParkingMeter(
            id: id,
            postId: properties.postId ?? "",
            streetName: properties.streetName,
            streetNum: properties.streetNum,
            geometry: geometry,
            activeMeterFlag: properties.activeMeterFlag,
            meterType: properties.meterType,
            meterVendor: properties.meterVendor,
            meterModel: properties.meterModel,
            capColor: properties.capColor,
            blockfaceId: properties.blockfaceId,
            pmDistrictId: properties.pmDistrictId
        )
    }
}

/// Properties from GeoJSON
struct ParkingMeterProperties: Codable {
    let id: String?
    let postId: String?
    let streetName: String?
    let streetNum: String?
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
        case activeMeterFlag = "active_meter_flag"
        case meterType = "meter_type"
        case meterVendor = "meter_vendor"
        case meterModel = "meter_model"
        case capColor = "cap_color"
        case blockfaceId = "blockface_id"
        case pmDistrictId = "pm_district_id"
    }
}

enum ParkingMeterLoaderError: Error {
    case fileNotFound
    case invalidData
}
