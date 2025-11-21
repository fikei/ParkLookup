import Foundation
import CoreLocation

/// High-level zone service combining lookup and interpretation
final class ZoneService: ZoneServiceProtocol {

    private let repository: ZoneRepository
    private let lookupEngine: ZoneLookupEngineProtocol
    private let ruleInterpreter: RuleInterpreterProtocol
    private let permitService: PermitServiceProtocol

    var dataVersion: String {
        repository.dataVersion
    }

    var isReady: Bool {
        lookupEngine.isReady
    }

    init(
        repository: ZoneRepository,
        lookupEngine: ZoneLookupEngineProtocol,
        ruleInterpreter: RuleInterpreterProtocol,
        permitService: PermitServiceProtocol
    ) {
        self.repository = repository
        self.lookupEngine = lookupEngine
        self.ruleInterpreter = ruleInterpreter
        self.permitService = permitService
    }

    func getParkingResult(at coordinate: CLLocationCoordinate2D, time: Date) async -> ParkingResult {
        // Perform zone lookup
        let lookupResult = await lookupEngine.findZone(at: coordinate)

        // Get user permits
        let userPermits = permitService.permits

        // Interpret rules for all zones
        var allInterpretations: [RuleInterpretationResult] = []
        var primaryInterpretation: RuleInterpretationResult?

        if !lookupResult.overlappingZones.isEmpty {
            allInterpretations = ruleInterpreter.interpretRules(
                for: lookupResult.overlappingZones,
                userPermits: userPermits,
                at: time
            )
            primaryInterpretation = allInterpretations.first
        }

        return ParkingResult(
            lookupResult: lookupResult,
            primaryInterpretation: primaryInterpretation,
            allInterpretations: allInterpretations,
            address: nil, // Will be populated by ViewModel
            timestamp: Date()
        )
    }

    func getAllZones(for city: CityIdentifier) async throws -> [ParkingZone] {
        try await repository.getZones(for: city)
    }
}
