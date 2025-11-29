import Foundation
import CoreLocation

// MARK: - Data Structures

/// Unified parking lookup result that works for both zones and blockfaces
struct ParkingLookupResult {
    /// Display name - Zone code ("Zone Q") or street name ("Mission St")
    let locationName: String

    /// Detailed location description (optional)
    let locationDetail: String?

    /// Primary regulation type affecting parking
    let primaryRegulationType: RegulationType

    /// Permit zones that apply (if RPP)
    let permitAreas: [String]?

    /// Time limit in minutes (if any)
    let timeLimitMinutes: Int?

    /// All regulations (for detail view)
    let allRegulations: [RegulationInfo]

    /// Next restriction that will end parking window
    let nextRestriction: RestrictionWindow?

    /// Source data for adapter-specific logic
    let sourceData: SourceData

    enum RegulationType {
        case free              // No restrictions
        case timeLimited       // Time limit only
        case residentialPermit // RPP zone
        case metered           // Paid parking
        case noParking         // No parking allowed
        case streetCleaning    // Street cleaning active
    }

    enum SourceData {
        case zone(ParkingZone)
        case blockface(Blockface)
    }
}

/// Detailed regulation information
struct RegulationInfo: Identifiable {
    let id = UUID()
    let type: ParkingLookupResult.RegulationType
    let description: String
    let enforcementDays: [DayOfWeek]?
    let enforcementStart: String?  // "08:00"
    let enforcementEnd: String?    // "18:00"
    let permitZone: String?
    let timeLimit: Int?  // minutes
}

/// Time window when parking is restricted
struct RestrictionWindow {
    let type: ParkingLookupResult.RegulationType
    let startsAt: Date
    let endsAt: Date
    let description: String
}

/// Result of park-until time calculation
struct ParkUntilResult {
    /// Time when user must move car
    let parkUntilTime: Date

    /// Reason for this time limit
    let reason: String

    /// Type of restriction causing the limit
    let restrictionType: ParkingLookupResult.RegulationType
}

// MARK: - Protocol

/// Unified interface for parking data lookup (zones or blockfaces)
protocol ParkingDataAdapterProtocol {
    /// Find parking information at a given coordinate
    func lookupParking(at coordinate: CLLocationCoordinate2D) async -> ParkingLookupResult?

    /// Calculate when user needs to move car
    func calculateParkUntil(
        for result: ParkingLookupResult,
        userPermits: Set<String>,
        parkingStartTime: Date
    ) -> ParkUntilResult?

    /// Check if user can park at this location
    func canPark(
        at result: ParkingLookupResult,
        userPermits: Set<String>,
        at time: Date
    ) -> Bool
}

// MARK: - Adapter Factory

/// Factory that returns the appropriate adapter based on feature flag
class ParkingDataAdapter {
    static var shared: ParkingDataAdapterProtocol {
        if DeveloperSettings.shared.useBlockfaceForFeatures {
            return BlockfaceDataAdapter()
        } else {
            return ZoneDataAdapter()
        }
    }
}

// MARK: - Zone-Based Adapter (Legacy System)

/// Adapter for legacy zone-based parking lookup
class ZoneDataAdapter: ParkingDataAdapterProtocol {
    private let zoneLookupEngine = ZoneLookupEngine()

    func lookupParking(at coordinate: CLLocationCoordinate2D) async -> ParkingLookupResult? {
        // Use existing zone lookup logic
        guard let result = zoneLookupEngine.lookup(coordinate: coordinate) else {
            return nil
        }

        // Convert zone result to unified format
        let primaryType: ParkingLookupResult.RegulationType
        if result.isInZone {
            if result.currentZone?.zoneType == .metered {
                primaryType = .metered
            } else if result.currentZone?.zoneType == .residentialPermit {
                primaryType = .residentialPermit
            } else if result.currentZone?.zoneType == .timeLimited {
                primaryType = .timeLimited
            } else {
                primaryType = .free
            }
        } else {
            primaryType = .free
        }

        // Extract permit areas
        let permitAreas: [String]?
        if let zone = result.currentZone, zone.zoneType == .residentialPermit {
            permitAreas = [zone.permitArea].compactMap { $0 }
        } else {
            permitAreas = nil
        }

        // Extract time limit
        let timeLimit = result.currentZone?.rules.first(where: { $0.ruleType == .timeLimit })?.timeLimit

        // Build regulations list
        var regulations: [RegulationInfo] = []
        if let zone = result.currentZone {
            for rule in zone.rules {
                let regType: ParkingLookupResult.RegulationType = {
                    switch rule.ruleType {
                    case .timeLimit: return .timeLimited
                    case .residential: return .residentialPermit
                    default: return .free
                    }
                }()

                regulations.append(RegulationInfo(
                    type: regType,
                    description: rule.displayString,
                    enforcementDays: rule.enforcementDays,
                    enforcementStart: rule.enforcementStartTime?.formatted,
                    enforcementEnd: rule.enforcementEndTime?.formatted,
                    permitZone: zone.zoneType == .residentialPermit ? zone.permitArea : nil,
                    timeLimit: rule.timeLimit
                ))
            }
        }

        // Determine next restriction (zones don't have street cleaning)
        let nextRestriction: RestrictionWindow? = nil

        return ParkingLookupResult(
            locationName: result.currentZone?.displayName ?? "No Zone",
            locationDetail: result.currentZone?.permitArea != nil ? "Zone \(result.currentZone!.permitArea!)" : nil,
            primaryRegulationType: primaryType,
            permitAreas: permitAreas,
            timeLimitMinutes: timeLimit,
            allRegulations: regulations,
            nextRestriction: nextRestriction,
            sourceData: result.currentZone.map { .zone($0) } ?? .zone(ParkingZone(
                id: "unknown",
                zoneType: .publicParking,
                geometry: ZoneGeometry(type: "Polygon", coordinates: []),
                rules: [],
                permitArea: nil,
                displayName: "Unknown"
            ))
        )
    }

    func calculateParkUntil(
        for result: ParkingLookupResult,
        userPermits: Set<String>,
        parkingStartTime: Date
    ) -> ParkUntilResult? {
        // Use existing time limit logic
        guard let timeLimit = result.timeLimitMinutes else {
            return nil
        }

        let parkUntilTime = parkingStartTime.addingTimeInterval(TimeInterval(timeLimit * 60))

        return ParkUntilResult(
            parkUntilTime: parkUntilTime,
            reason: "\(timeLimit) minute time limit",
            restrictionType: .timeLimited
        )
    }

    func canPark(
        at result: ParkingLookupResult,
        userPermits: Set<String>,
        at time: Date
    ) -> Bool {
        // Zone-based permission logic
        switch result.primaryRegulationType {
        case .free:
            return true
        case .residentialPermit:
            if let permitAreas = result.permitAreas {
                return !userPermits.isDisjoint(with: Set(permitAreas))
            }
            return false
        case .metered, .timeLimited:
            return true  // Can park but with restrictions
        case .noParking, .streetCleaning:
            return false
        }
    }
}

// MARK: - Blockface-Based Adapter (New System)

/// Adapter for blockface-based parking lookup
class BlockfaceDataAdapter: ParkingDataAdapterProtocol {
    func lookupParking(at coordinate: CLLocationCoordinate2D) async -> ParkingLookupResult? {
        // TODO: Implement blockface lookup with closest-block logic
        // - Find blockfaces within 50m
        // - Prefer same side of street
        // - Sticky preference for last closest block
        return nil
    }

    func calculateParkUntil(
        for result: ParkingLookupResult,
        userPermits: Set<String>,
        parkingStartTime: Date
    ) -> ParkUntilResult? {
        // TODO: Implement blockface-based park until
        // - Consider all regulations
        // - Use most restrictive time
        // - Account for street cleaning windows
        return nil
    }

    func canPark(
        at result: ParkingLookupResult,
        userPermits: Set<String>,
        at time: Date
    ) -> Bool {
        // TODO: Implement blockface permission logic
        // - Check all regulations
        // - Permit exempts from meter if zone matches
        // - Street cleaning overrides permit
        return false
    }
}

// MARK: - Extensions

extension TimeOfDay {
    var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }
}
