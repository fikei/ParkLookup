import Foundation
import UIKit
import CoreLocation

/// Protocol for map provider abstraction (Google Maps, MapLibre, etc.)
protocol MapProviderProtocol {
    /// Create a map view with the given configuration
    /// - Parameter configuration: Map configuration options
    /// - Returns: UIView containing the map
    func createMapView(configuration: MapConfiguration) -> UIView

    /// Set the map center
    /// - Parameters:
    ///   - coordinate: Center coordinate
    ///   - animated: Whether to animate the transition
    func setCenter(_ coordinate: CLLocationCoordinate2D, animated: Bool)

    /// Set the zoom level
    /// - Parameters:
    ///   - level: Zoom level (typically 1-20)
    ///   - animated: Whether to animate the transition
    func setZoomLevel(_ level: Float, animated: Bool)

    /// Add a polygon overlay to the map
    /// - Parameter polygon: The polygon to add
    /// - Returns: Identifier for the polygon (for later removal)
    func addPolygon(_ polygon: MapPolygon) -> String

    /// Remove a polygon from the map
    /// - Parameter id: The polygon identifier
    func removePolygon(id: String)

    /// Add a marker to the map
    /// - Parameter marker: The marker to add
    /// - Returns: Identifier for the marker
    func addMarker(_ marker: MapMarker) -> String

    /// Remove a marker from the map
    /// - Parameter id: The marker identifier
    func removeMarker(id: String)

    /// Show or hide the user location dot
    /// - Parameter visible: Whether user location should be visible
    func setUserLocationVisible(_ visible: Bool)

    /// Set the map style
    /// - Parameter style: The style to apply
    func setMapStyle(_ style: MapStyle)

    /// Current map center coordinate
    var center: CLLocationCoordinate2D { get }

    /// Current zoom level
    var zoomLevel: Float { get }
}

// MARK: - Map Configuration

struct MapConfiguration {
    let initialCenter: CLLocationCoordinate2D
    let initialZoom: Float
    let style: MapStyle
    let isUserInteractionEnabled: Bool
    let showsUserLocation: Bool

    static let `default` = MapConfiguration(
        initialCenter: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // SF center
        initialZoom: 15,
        style: .light,
        isUserInteractionEnabled: true,
        showsUserLocation: true
    )

    static let minimized = MapConfiguration(
        initialCenter: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        initialZoom: 16,
        style: .light,
        isUserInteractionEnabled: false,
        showsUserLocation: true
    )
}

// MARK: - Map Style

enum MapStyle: String, CaseIterable, Codable {
    case light
    case dark
    case satellite

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .satellite: return "Satellite"
        }
    }
}

// MARK: - Map Overlay Types

struct MapPolygon {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let fillColor: UIColor
    let strokeColor: UIColor
    let strokeWidth: CGFloat

    init(
        id: String = UUID().uuidString,
        coordinates: [CLLocationCoordinate2D],
        fillColor: UIColor = .blue.withAlphaComponent(0.2),
        strokeColor: UIColor = .blue,
        strokeWidth: CGFloat = 2
    ) {
        self.id = id
        self.coordinates = coordinates
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }
}

struct MapMarker {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let icon: UIImage?

    init(
        id: String = UUID().uuidString,
        coordinate: CLLocationCoordinate2D,
        title: String? = nil,
        icon: UIImage? = nil
    ) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
        self.icon = icon
    }
}
