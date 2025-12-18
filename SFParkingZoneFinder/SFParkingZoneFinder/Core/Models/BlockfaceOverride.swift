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
    /// Note: Creates a new regulation with a new UUID
    func toBlockfaceRegulation() -> BlockfaceRegulation {
        // Use JSONEncoder/Decoder to create a proper instance with all CodingKeys
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Create a dictionary representation
        let dict: [String: Any?] = [
            "type": type,
            "permitZone": permitZone,
            "permitZones": permitZones,
            "timeLimit": timeLimit,
            "meterRate": meterRate.map { NSDecimalNumber(decimal: $0).doubleValue },
            "enforcementDays": enforcementDays,
            "enforcementStart": enforcementStart,
            "enforcementEnd": enforcementEnd,
            "specialConditions": specialConditions
        ]

        // Filter out nil values
        let filtered = dict.compactMapValues { $0 }

        do {
            let data = try JSONSerialization.data(withJSONObject: filtered)
            return try decoder.decode(BlockfaceRegulation.self, from: data)
        } catch {
            // Fallback: This should never happen, but if it does, we'll handle it gracefully
            fatalError("Failed to convert BlockfaceRegulationOverride to BlockfaceRegulation: \(error)")
        }
    }
}
