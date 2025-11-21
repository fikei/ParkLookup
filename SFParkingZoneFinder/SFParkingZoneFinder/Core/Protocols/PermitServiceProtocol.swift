import Foundation
import Combine

/// Protocol for permit management service
protocol PermitServiceProtocol {
    /// All user permits
    var permits: [ParkingPermit] { get }

    /// Publisher for permit changes
    var permitsPublisher: AnyPublisher<[ParkingPermit], Never> { get }

    /// Add a new permit
    /// - Parameter permit: The permit to add
    func addPermit(_ permit: ParkingPermit)

    /// Remove a permit
    /// - Parameter permit: The permit to remove
    func removePermit(_ permit: ParkingPermit)

    /// Update an existing permit
    /// - Parameter permit: The permit with updated values
    func updatePermit(_ permit: ParkingPermit)

    /// Set a permit as the primary permit
    /// - Parameter permit: The permit to make primary
    func setPrimaryPermit(_ permit: ParkingPermit)

    /// Get the primary permit (if any)
    var primaryPermit: ParkingPermit? { get }

    /// Remove all permits
    func removeAllPermits()

    /// Check if user has any permits
    var hasPermits: Bool { get }
}
