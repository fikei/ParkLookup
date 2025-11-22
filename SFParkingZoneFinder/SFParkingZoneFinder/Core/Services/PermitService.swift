import Foundation
import Combine

/// Service for managing user parking permits
final class PermitService: PermitServiceProtocol {

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let permitsKey = "user_parking_permits"
    private let primaryPermitKey = "primary_permit_id"

    private let permitsSubject = CurrentValueSubject<[ParkingPermit], Never>([])

    var permits: [ParkingPermit] {
        permitsSubject.value
    }

    var permitsPublisher: AnyPublisher<[ParkingPermit], Never> {
        permitsSubject.eraseToAnyPublisher()
    }

    var primaryPermit: ParkingPermit? {
        permits.first { $0.isPrimary } ?? permits.first
    }

    var hasPermits: Bool {
        !permits.isEmpty
    }

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadPermits()
    }

    // MARK: - PermitServiceProtocol

    func addPermit(_ permit: ParkingPermit) {
        var currentPermits = permits

        // If this is the first permit, make it primary
        var newPermit = permit
        if currentPermits.isEmpty {
            newPermit = ParkingPermit(
                id: permit.id,
                type: permit.type,
                area: permit.area,
                cityCode: permit.cityCode,
                expirationDate: permit.expirationDate,
                isPrimary: true,
                createdAt: permit.createdAt
            )
        }

        currentPermits.append(newPermit)
        savePermits(currentPermits)
    }

    func removePermit(_ permit: ParkingPermit) {
        var currentPermits = permits
        currentPermits.removeAll { $0.id == permit.id }

        // If we removed the primary, set a new primary
        if permit.isPrimary, let first = currentPermits.first {
            if let index = currentPermits.firstIndex(where: { $0.id == first.id }) {
                var updated = currentPermits[index]
                updated = ParkingPermit(
                    id: updated.id,
                    type: updated.type,
                    area: updated.area,
                    cityCode: updated.cityCode,
                    expirationDate: updated.expirationDate,
                    isPrimary: true,
                    createdAt: updated.createdAt
                )
                currentPermits[index] = updated
            }
        }

        savePermits(currentPermits)
    }

    func updatePermit(_ permit: ParkingPermit) {
        var currentPermits = permits
        if let index = currentPermits.firstIndex(where: { $0.id == permit.id }) {
            currentPermits[index] = permit
            savePermits(currentPermits)
        }
    }

    func setPrimaryPermit(_ permit: ParkingPermit) {
        var currentPermits = permits

        // Remove primary from all
        currentPermits = currentPermits.map { p in
            ParkingPermit(
                id: p.id,
                type: p.type,
                area: p.area,
                cityCode: p.cityCode,
                expirationDate: p.expirationDate,
                isPrimary: p.id == permit.id,
                createdAt: p.createdAt
            )
        }

        savePermits(currentPermits)
    }

    func removeAllPermits() {
        savePermits([])
    }

    // MARK: - Persistence

    private func loadPermits() {
        guard let data = userDefaults.data(forKey: permitsKey) else {
            permitsSubject.send([])
            return
        }

        do {
            let permits = try JSONDecoder().decode([ParkingPermit].self, from: data)
            permitsSubject.send(permits)
        } catch {
            print("Failed to load permits: \(error)")
            permitsSubject.send([])
        }
    }

    private func savePermits(_ permits: [ParkingPermit]) {
        do {
            let data = try JSONEncoder().encode(permits)
            userDefaults.set(data, forKey: permitsKey)
            permitsSubject.send(permits)
        } catch {
            print("Failed to save permits: \(error)")
        }
    }
}
