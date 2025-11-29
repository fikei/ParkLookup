import Foundation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ParkingMeterLoader")

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
