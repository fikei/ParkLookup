import Foundation

/// Represents a reverse-geocoded address
struct Address: Codable {
    let streetNumber: String?
    let streetName: String?
    let neighborhood: String?
    let city: String?
    let formattedAddress: String

    init(
        streetNumber: String? = nil,
        streetName: String? = nil,
        neighborhood: String? = nil,
        city: String? = nil,
        formattedAddress: String
    ) {
        self.streetNumber = streetNumber
        self.streetName = streetName
        self.neighborhood = neighborhood
        self.city = city
        self.formattedAddress = formattedAddress
    }
}

// MARK: - Computed Properties

extension Address {
    /// Short address (street only)
    var shortAddress: String {
        var parts: [String] = []
        if let number = streetNumber {
            parts.append(number)
        }
        if let street = streetName {
            parts.append(street)
        }
        return parts.isEmpty ? formattedAddress : parts.joined(separator: " ")
    }

    /// Whether address has meaningful data
    var isValid: Bool {
        !formattedAddress.isEmpty
    }
}

// MARK: - Factory

extension Address {
    /// Create an unknown/placeholder address
    static var unknown: Address {
        Address(formattedAddress: "Address unavailable")
    }
}
