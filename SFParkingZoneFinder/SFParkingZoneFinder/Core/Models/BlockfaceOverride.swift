import Foundation

/// Represents developer overrides for blockface regulations
/// Used in development mode to test different parking scenarios
struct BlockfaceOverride: Codable, Identifiable {
    let id: String  // Blockface ID
    let regulations: [BlockfaceRegulationOverride]
    let createdAt: Date
    let notes: String?

    init(id: String, regulations: [BlockfaceRegulationOverride], notes: String? = nil) {
        self.id = id
        self.regulations = regulations
        self.createdAt = Date()
        self.notes = notes
    }
}

/// Editable version of BlockfaceRegulation for overrides
struct BlockfaceRegulationOverride: Codable, Identifiable {
    var id: UUID
    var type: String
    var permitZone: String?
    var permitZones: [String]?
    var timeLimit: Int?
    var meterRate: Decimal?
    var enforcementDays: [String]?
    var enforcementStart: String?
    var enforcementEnd: String?
    var specialConditions: String?

    /// Create from existing regulation
    init(from regulation: BlockfaceRegulation) {
        self.id = regulation.id
        self.type = regulation.type
        self.permitZone = regulation.permitZone
        self.permitZones = regulation.permitZones
        self.timeLimit = regulation.timeLimit
        self.meterRate = regulation.meterRate
        self.enforcementDays = regulation.enforcementDays
        self.enforcementStart = regulation.enforcementStart
        self.enforcementEnd = regulation.enforcementEnd
        self.specialConditions = regulation.specialConditions
    }

    /// Create new blank regulation
    init(type: String) {
        self.id = UUID()
        self.type = type
        self.permitZone = nil
        self.permitZones = nil
        self.timeLimit = nil
        self.meterRate = nil
        self.enforcementDays = nil
        self.enforcementStart = nil
        self.enforcementEnd = nil
        self.specialConditions = nil
    }

    /// Convert to BlockfaceRegulation
    func toBlockfaceRegulation() -> BlockfaceRegulation {
        BlockfaceRegulation(
            type: type,
            permitZone: permitZone,
            permitZones: permitZones,
            timeLimit: timeLimit,
            meterRate: meterRate,
            enforcementDays: enforcementDays,
            enforcementStart: enforcementStart,
            enforcementEnd: enforcementEnd,
            specialConditions: specialConditions
        )
    }
}

// Need to add a custom init to BlockfaceRegulation in the original file
extension BlockfaceRegulation {
    /// Initialize with all properties (for overrides)
    init(type: String,
         permitZone: String? = nil,
         permitZones: [String]? = nil,
         timeLimit: Int? = nil,
         meterRate: Decimal? = nil,
         enforcementDays: [String]? = nil,
         enforcementStart: String? = nil,
         enforcementEnd: String? = nil,
         specialConditions: String? = nil) {
        self.type = type
        self.permitZone = permitZone
        self.permitZones = permitZones
        self.timeLimit = timeLimit
        self.meterRate = meterRate
        self.enforcementDays = enforcementDays
        self.enforcementStart = enforcementStart
        self.enforcementEnd = enforcementEnd
        self.specialConditions = specialConditions
    }
}
