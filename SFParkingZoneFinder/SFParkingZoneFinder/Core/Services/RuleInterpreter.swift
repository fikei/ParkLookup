import Foundation

/// Interprets parking rules and determines permit validity
final class RuleInterpreter: RuleInterpreterProtocol {

    func interpretRules(
        for zone: ParkingZone,
        userPermits: [ParkingPermit],
        at time: Date
    ) -> RuleInterpretationResult {

        // Check if zone requires a permit
        guard zone.requiresPermit else {
            return createNoPermitRequiredResult(zone: zone)
        }

        // Find matching permits
        let matchingPermits = userPermits.filter { permit in
            zone.validPermitAreas.contains(permit.area) && !permit.isExpired
        }

        // Determine validity status
        let status: PermitValidityStatus
        switch matchingPermits.count {
        case 0:
            status = .invalid
        case 1:
            status = .valid
        default:
            status = .multipleApply
        }

        // Check for conditional rules (flag but don't enforce)
        let conditionalFlags = identifyConditionalRules(zone: zone, time: time)

        // Generate rule summary
        let summary = generateRuleSummary(zone: zone, status: status)

        // Generate warnings
        let warnings = generateWarnings(zone: zone, time: time)

        return RuleInterpretationResult(
            validityStatus: status,
            applicablePermits: matchingPermits,
            ruleSummary: summary,
            detailedRules: zone.rules,
            warnings: warnings,
            conditionalFlags: conditionalFlags,
            zone: zone
        )
    }

    func interpretRules(
        for zones: [ParkingZone],
        userPermits: [ParkingPermit],
        at time: Date
    ) -> [RuleInterpretationResult] {
        zones.map { interpretRules(for: $0, userPermits: userPermits, at: time) }
            .sorted { $0.zone.restrictiveness > $1.zone.restrictiveness }
    }

    // MARK: - Private Helpers

    private func createNoPermitRequiredResult(zone: ParkingZone) -> RuleInterpretationResult {
        RuleInterpretationResult(
            validityStatus: .noPermitRequired,
            applicablePermits: [],
            ruleSummary: generateRuleSummary(zone: zone, status: .noPermitRequired),
            detailedRules: zone.rules,
            warnings: [],
            conditionalFlags: [],
            zone: zone
        )
    }

    private func identifyConditionalRules(zone: ParkingZone, time: Date) -> [ConditionalFlag] {
        var flags: [ConditionalFlag] = []

        // Check for time-based restrictions
        if zone.hasTimeRestrictions {
            flags.append(ConditionalFlag(
                type: .timeOfDayRestriction,
                description: zone.timeRestrictionDescription,
                requiresImplementation: false
            ))
        }

        // Check for metered zones
        if zone.zoneType == .metered {
            flags.append(ConditionalFlag(
                type: .meterRequired,
                description: "Meter payment may be required",
                requiresImplementation: false
            ))
        }

        return flags
    }

    private func generateRuleSummary(zone: ParkingZone, status: PermitValidityStatus) -> String {
        var lines: [String] = []

        // Zone type
        lines.append(zone.displayName)

        // Permit requirement
        if zone.requiresPermit, let area = zone.permitArea {
            lines.append("Residential Permit Area \(area) only")
        }

        // Time limits
        if let limit = zone.nonPermitTimeLimit {
            let hours = limit / 60
            let limitText = hours > 0 ? "\(hours)-hour" : "\(limit)-minute"
            lines.append("\(limitText) limit for non-permit holders")
        }

        // Enforcement hours
        if let hours = zone.enforcementHours {
            lines.append("Enforced \(hours)")
        }

        // Street cleaning
        if let cleaning = zone.streetCleaning {
            lines.append("Street cleaning: \(cleaning)")
        }

        return lines.joined(separator: "\n")
    }

    private func generateWarnings(zone: ParkingZone, time: Date) -> [ParkingWarning] {
        var warnings: [ParkingWarning] = []

        // Check street cleaning rules
        for rule in zone.rules where rule.ruleType == .streetCleaning {
            if rule.isInEffect(at: time) {
                warnings.append(ParkingWarning(
                    type: .streetCleaning,
                    message: "Street cleaning in effect!",
                    severity: .high
                ))
            }
        }

        // Check tow-away zones
        if zone.zoneType == .towAway {
            warnings.append(ParkingWarning(
                type: .towAway,
                message: "Tow-away zone - do not park here",
                severity: .high
            ))
        }

        return warnings
    }
}
