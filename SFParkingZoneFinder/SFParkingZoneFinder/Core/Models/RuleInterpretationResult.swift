import Foundation

/// Result of interpreting parking rules for a zone
struct RuleInterpretationResult {
    /// Overall permit validity status
    let validityStatus: PermitValidityStatus

    /// User's permits that are valid for this zone
    let applicablePermits: [ParkingPermit]

    /// Human-readable summary of rules
    let ruleSummary: String

    /// All rules for the zone
    let detailedRules: [ParkingRule]

    /// Active warnings (street cleaning, time limits, etc.)
    let warnings: [ParkingWarning]

    /// Conditional rules flagged for display (not enforced in V1)
    let conditionalFlags: [ConditionalFlag]

    /// The zone this interpretation is for
    let zone: ParkingZone
}

// MARK: - Computed Properties

extension RuleInterpretationResult {
    /// Whether any permits are valid
    var hasValidPermit: Bool {
        !applicablePermits.isEmpty
    }

    /// Whether there are active warnings
    var hasWarnings: Bool {
        !warnings.isEmpty
    }

    /// Whether there are conditional flags to display
    var hasConditionalFlags: Bool {
        !conditionalFlags.isEmpty
    }

    /// Summary lines as array (for bullet display)
    var ruleSummaryLines: [String] {
        ruleSummary.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

// MARK: - Permit Validity Status

enum PermitValidityStatus: String, Codable {
    /// Permit is valid - user can park
    case valid

    /// Permit is not valid - user cannot park (or has time limit)
    case invalid

    /// Permit valid with conditions (time restrictions apply)
    case conditional

    /// No permit required - anyone can park
    case noPermitRequired

    /// Multiple user permits are valid here
    case multipleApply

    /// User has no permits configured - prompt to add one
    case noPermitSet

    var displayText: String {
        switch self {
        case .valid:
            return "YOUR PERMIT IS VALID HERE"
        case .invalid:
            return "YOUR PERMIT IS NOT VALID HERE"
        case .conditional:
            return "CONDITIONAL - SEE RULES BELOW"
        case .noPermitRequired:
            return "NO PERMIT REQUIRED"
        case .multipleApply:
            return "MULTIPLE PERMITS APPLY"
        case .noPermitSet:
            return "PERMIT REQUIRED"
        }
    }

    var shortText: String {
        switch self {
        case .valid: return "Valid"
        case .invalid: return "Not Valid"
        case .conditional: return "Conditional"
        case .noPermitRequired: return "No Permit Needed"
        case .multipleApply: return "Multiple Valid"
        case .noPermitSet: return "Permit Required"
        }
    }

    var iconName: String {
        switch self {
        case .valid:
            return "checkmark.circle.fill"
        case .invalid:
            return "xmark.circle.fill"
        case .conditional:
            return "exclamationmark.triangle.fill"
        case .noPermitRequired:
            return "parkingsign.circle.fill"
        case .multipleApply:
            return "checkmark.circle.badge.checkmark.fill"
        case .noPermitSet:
            return "parkingsign.circle"
        }
    }
}

// MARK: - Parking Warning

struct ParkingWarning: Identifiable {
    let id: String
    let type: WarningType
    let message: String
    let severity: WarningSeverity

    init(
        id: String = UUID().uuidString,
        type: WarningType,
        message: String,
        severity: WarningSeverity = .medium
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.severity = severity
    }
}

enum WarningType: String {
    case streetCleaning
    case timeLimit
    case meterExpiring
    case towAway
    case specialEvent
}

enum WarningSeverity: String {
    case low
    case medium
    case high
}

// MARK: - Conditional Flag

struct ConditionalFlag: Identifiable {
    let id: String
    let type: ConditionalType
    let description: String
    let requiresImplementation: Bool  // false = display only in V1

    init(
        id: String = UUID().uuidString,
        type: ConditionalType,
        description: String,
        requiresImplementation: Bool = false
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.requiresImplementation = requiresImplementation
    }
}

enum ConditionalType: String {
    case timeOfDayRestriction
    case dayOfWeekRestriction
    case specialEventRestriction
    case temporaryRestriction
    case meterRequired
}
