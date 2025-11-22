import Foundation

/// Protocol for rule interpretation engine
protocol RuleInterpreterProtocol {
    /// Interpret parking rules for a zone given user's permits
    /// - Parameters:
    ///   - zone: The parking zone to interpret rules for
    ///   - userPermits: User's parking permits
    ///   - time: The time to evaluate rules at (for time-based restrictions)
    /// - Returns: Interpretation result with validity status and rule summary
    func interpretRules(
        for zone: ParkingZone,
        userPermits: [ParkingPermit],
        at time: Date
    ) -> RuleInterpretationResult

    /// Interpret rules for multiple zones (for overlapping zone scenarios)
    /// - Parameters:
    ///   - zones: The parking zones to interpret
    ///   - userPermits: User's parking permits
    ///   - time: The time to evaluate rules at
    /// - Returns: Array of interpretation results, sorted by restrictiveness
    func interpretRules(
        for zones: [ParkingZone],
        userPermits: [ParkingPermit],
        at time: Date
    ) -> [RuleInterpretationResult]
}
