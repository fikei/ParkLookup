import Foundation

/// Manages developer overrides for blockface regulations
/// Stores overrides in UserDefaults for development/testing purposes
class BlockfaceOverrideManager: ObservableObject {
    static let shared = BlockfaceOverrideManager()

    private let overridesKey = "dev.blockfaceOverrides"

    @Published private(set) var overrides: [String: BlockfaceOverride] = [:]

    init() {
        loadOverrides()
    }

    // MARK: - Public API

    /// Save an override for a specific blockface
    func saveOverride(_ override: BlockfaceOverride) {
        overrides[override.id] = override
        persistOverrides()
        postChangeNotification()
    }

    /// Get override for a specific blockface
    func getOverride(for blockfaceId: String) -> BlockfaceOverride? {
        overrides[blockfaceId]
    }

    /// Remove override for a specific blockface
    func removeOverride(for blockfaceId: String) {
        overrides.removeValue(forKey: blockfaceId)
        persistOverrides()
        postChangeNotification()
    }

    /// Clear all overrides
    func clearAllOverrides() {
        overrides.removeAll()
        persistOverrides()
        postChangeNotification()
    }

    /// Check if a blockface has an override
    func hasOverride(for blockfaceId: String) -> Bool {
        overrides[blockfaceId] != nil
    }

    /// Apply overrides to a blockface
    func applyOverride(to blockface: Blockface) -> Blockface? {
        guard let override = overrides[blockface.id] else {
            return nil
        }

        // Create new blockface with overridden regulations
        let overriddenRegulations = override.regulations.map { $0.toBlockfaceRegulation() }

        // Use JSON encoding/decoding to create a modified copy
        do {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            // Encode the original blockface
            var data = try encoder.encode(blockface)

            // Decode to dictionary, modify regulations, re-encode
            var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            // Replace regulations with overridden ones
            let regulationsData = try encoder.encode(overriddenRegulations)
            let regulationsArray = try JSONSerialization.jsonObject(with: regulationsData)
            dict["regulations"] = regulationsArray

            // Convert back to Blockface
            data = try JSONSerialization.data(withJSONObject: dict)
            return try decoder.decode(Blockface.self, from: data)
        } catch {
            print("⚠️ Failed to apply override to blockface \(blockface.id): \(error)")
            return nil
        }
    }

    /// Export overrides as JSON (for sharing or testing)
    func exportOverrides() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(Array(overrides.values)),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
    }

    /// Import overrides from JSON
    func importOverrides(from json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw OverrideError.invalidJSON
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let importedOverrides = try decoder.decode([BlockfaceOverride].self, from: data)

        for override in importedOverrides {
            overrides[override.id] = override
        }

        persistOverrides()
        postChangeNotification()
    }

    /// Get statistics about overrides
    var statistics: OverrideStatistics {
        OverrideStatistics(
            totalOverrides: overrides.count,
            totalRegulations: overrides.values.reduce(0) { $0 + $1.regulations.count },
            oldestOverride: overrides.values.map { $0.createdAt }.min(),
            newestOverride: overrides.values.map { $0.createdAt }.max()
        )
    }

    // MARK: - Private Methods

    private func loadOverrides() {
        guard let data = UserDefaults.standard.data(forKey: overridesKey) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let loadedOverrides = try decoder.decode([BlockfaceOverride].self, from: data)
            overrides = Dictionary(uniqueKeysWithValues: loadedOverrides.map { ($0.id, $0) })
        } catch {
            print("⚠️ Failed to load blockface overrides: \(error)")
            // Clear corrupted data
            UserDefaults.standard.removeObject(forKey: overridesKey)
        }
    }

    private func persistOverrides() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(Array(overrides.values))
            UserDefaults.standard.set(data, forKey: overridesKey)
        } catch {
            print("⚠️ Failed to persist blockface overrides: \(error)")
        }
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(
            name: .blockfaceOverridesChanged,
            object: nil
        )
    }
}

// MARK: - Supporting Types

enum OverrideError: Error, LocalizedError {
    case invalidJSON
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON format"
        case .decodingFailed:
            return "Failed to decode overrides"
        }
    }
}

struct OverrideStatistics {
    let totalOverrides: Int
    let totalRegulations: Int
    let oldestOverride: Date?
    let newestOverride: Date?
}
