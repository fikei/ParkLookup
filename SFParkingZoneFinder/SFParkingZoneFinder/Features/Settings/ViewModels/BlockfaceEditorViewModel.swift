import Foundation
import CoreLocation
import Combine

/// View model for the blockface regulation editor
@MainActor
class BlockfaceEditorViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedBlockface: Blockface?
    @Published var editableRegulations: [BlockfaceRegulationOverride] = []
    @Published var nearbyBlockfaces: [Blockface] = []
    @Published var isLoading = false
    @Published var showingRegulationEditor = false
    @Published var editingRegulationIndex: Int?

    // MARK: - Private Properties

    private var originalRegulations: [BlockfaceRegulationOverride] = []
    private let overrideManager = BlockfaceOverrideManager.shared
    private let blockfaceLoader = BlockfaceLoader.shared
    private var locationManager: CLLocationManager?

    // MARK: - Computed Properties

    var hasChanges: Bool {
        editableRegulations != originalRegulations
    }

    var hasOverride: Bool {
        guard let blockfaceId = selectedBlockface?.id else { return false }
        return overrideManager.hasOverride(for: blockfaceId)
    }

    // MARK: - Public Methods

    /// Load blockfaces near the current location
    func loadNearbyBlockfaces() {
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                // Get current location
                guard let location = await getCurrentLocation() else {
                    print("⚠️ Could not get current location")
                    return
                }

                // Load nearby blockfaces
                nearbyBlockfaces = try await blockfaceLoader.loadBlockfacesNear(
                    coordinate: location.coordinate,
                    radiusMeters: 200,
                    maxCount: 50
                )

                print("✅ Loaded \(nearbyBlockfaces.count) nearby blockfaces")
            } catch {
                print("❌ Error loading blockfaces: \(error)")
            }
        }
    }

    /// Select a blockface to edit
    func selectBlockface(_ blockface: Blockface) {
        selectedBlockface = blockface

        // Load existing override or use current regulations
        if let override = overrideManager.getOverride(for: blockface.id) {
            editableRegulations = override.regulations
        } else {
            editableRegulations = blockface.regulations.map { BlockfaceRegulationOverride(from: $0) }
        }

        originalRegulations = editableRegulations
    }

    /// Add a new regulation
    func addNewRegulation() {
        let newRegulation = BlockfaceRegulationOverride(type: "timeLimit")
        editableRegulations.append(newRegulation)
        editingRegulationIndex = editableRegulations.count - 1
        showingRegulationEditor = true
    }

    /// Edit an existing regulation
    func editRegulation(at index: Int) {
        editingRegulationIndex = index
        showingRegulationEditor = true
    }

    /// Delete a regulation
    func deleteRegulation(at index: Int) {
        editableRegulations.remove(at: index)
        showingRegulationEditor = false
        editingRegulationIndex = nil
    }

    /// Delete regulations at indices
    func deleteRegulations(at indexSet: IndexSet) {
        editableRegulations.remove(atOffsets: indexSet)
    }

    /// Save the override
    func saveOverride() {
        guard let blockface = selectedBlockface else { return }

        let override = BlockfaceOverride(
            id: blockface.id,
            regulations: editableRegulations,
            notes: "Modified via developer mode"
        )

        overrideManager.saveOverride(override)
        print("✅ Saved override for blockface \(blockface.id)")
    }

    /// Remove the override for the current blockface
    func removeOverride() {
        guard let blockface = selectedBlockface else { return }
        overrideManager.removeOverride(for: blockface.id)

        // Reset to original regulations
        editableRegulations = blockface.regulations.map { BlockfaceRegulationOverride(from: $0) }
        originalRegulations = editableRegulations

        print("✅ Removed override for blockface \(blockface.id)")
    }

    /// Load a specific blockface by ID
    func loadBlockface(id: String) {
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                // This is a simplified implementation - you might need to search through all blockfaces
                // For now, we'll just log that this functionality needs implementation
                print("⚠️ loadBlockface(id:) not yet fully implemented")
            } catch {
                print("❌ Error loading blockface: \(error)")
            }
        }
    }

    // MARK: - Private Methods

    private func getCurrentLocation() async -> CLLocation? {
        return await withCheckedContinuation { continuation in
            let manager = CLLocationManager()
            self.locationManager = manager

            // Check authorization status
            let status = manager.authorizationStatus

            if status == .notDetermined {
                // Request authorization
                manager.requestWhenInUseAuthorization()
            }

            // Get location
            if let location = manager.location {
                continuation.resume(returning: location)
            } else {
                // Default to San Francisco center if no location available
                let defaultLocation = CLLocation(
                    latitude: 37.7749,
                    longitude: -122.4194
                )
                continuation.resume(returning: defaultLocation)
            }
        }
    }
}

// MARK: - Equatable Conformance

extension BlockfaceRegulationOverride: Equatable {
    static func == (lhs: BlockfaceRegulationOverride, rhs: BlockfaceRegulationOverride) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.permitZone == rhs.permitZone &&
        lhs.permitZones == rhs.permitZones &&
        lhs.timeLimit == rhs.timeLimit &&
        lhs.meterRate == rhs.meterRate &&
        lhs.enforcementDays == rhs.enforcementDays &&
        lhs.enforcementStart == rhs.enforcementStart &&
        lhs.enforcementEnd == rhs.enforcementEnd &&
        lhs.specialConditions == rhs.specialConditions
    }
}
