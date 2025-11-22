import Foundation
import UIKit
import CoreLocation

// Conditional import - only import GoogleMaps if available
#if canImport(GoogleMaps)
import GoogleMaps
private let googleMapsAvailable = true
#else
private let googleMapsAvailable = false
#endif

/// Google Maps SDK implementation of MapProviderProtocol
/// Falls back to placeholder view if Google Maps SDK is not installed
final class GoogleMapsAdapter: MapProviderProtocol {

    private var mapView: UIView?
    private var polygonIds: Set<String> = []
    private var markerIds: Set<String> = []

    private var _center: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    private var _zoomLevel: Float = 15

    var center: CLLocationCoordinate2D {
        #if canImport(GoogleMaps)
        if let gmsView = mapView as? GMSMapView {
            return gmsView.camera.target
        }
        #endif
        return _center
    }

    var zoomLevel: Float {
        #if canImport(GoogleMaps)
        if let gmsView = mapView as? GMSMapView {
            return gmsView.camera.zoom
        }
        #endif
        return _zoomLevel
    }

    func createMapView(configuration: MapConfiguration) -> UIView {
        _center = configuration.initialCenter
        _zoomLevel = configuration.initialZoom

        #if canImport(GoogleMaps)
        let camera = GMSCameraPosition.camera(
            withTarget: configuration.initialCenter,
            zoom: configuration.initialZoom
        )

        let gmsMapView = GMSMapView(frame: .zero, camera: camera)
        gmsMapView.isMyLocationEnabled = configuration.showsUserLocation
        gmsMapView.settings.myLocationButton = false
        gmsMapView.settings.scrollGestures = configuration.isUserInteractionEnabled
        gmsMapView.settings.zoomGestures = configuration.isUserInteractionEnabled
        gmsMapView.settings.rotateGestures = configuration.isUserInteractionEnabled
        gmsMapView.settings.tiltGestures = false

        applyStyle(configuration.style, to: gmsMapView)

        self.mapView = gmsMapView
        return gmsMapView
        #else
        // Fallback placeholder when Google Maps SDK is not available
        let placeholder = MapPlaceholderView(configuration: configuration)
        self.mapView = placeholder
        return placeholder
        #endif
    }

    func setCenter(_ coordinate: CLLocationCoordinate2D, animated: Bool) {
        _center = coordinate
        #if canImport(GoogleMaps)
        guard let gmsView = mapView as? GMSMapView else { return }
        if animated {
            gmsView.animate(toLocation: coordinate)
        } else {
            gmsView.camera = GMSCameraPosition.camera(
                withTarget: coordinate,
                zoom: gmsView.camera.zoom
            )
        }
        #endif
    }

    func setZoomLevel(_ level: Float, animated: Bool) {
        _zoomLevel = level
        #if canImport(GoogleMaps)
        guard let gmsView = mapView as? GMSMapView else { return }
        if animated {
            gmsView.animate(toZoom: level)
        } else {
            gmsView.camera = GMSCameraPosition.camera(
                withTarget: gmsView.camera.target,
                zoom: level
            )
        }
        #endif
    }

    func addPolygon(_ polygon: MapPolygon) -> String {
        polygonIds.insert(polygon.id)

        #if canImport(GoogleMaps)
        guard let gmsView = mapView as? GMSMapView else { return polygon.id }

        let path = GMSMutablePath()
        for coordinate in polygon.coordinates {
            path.add(coordinate)
        }

        let gmsPolygon = GMSPolygon(path: path)
        gmsPolygon.fillColor = polygon.fillColor
        gmsPolygon.strokeColor = polygon.strokeColor
        gmsPolygon.strokeWidth = polygon.strokeWidth
        gmsPolygon.isTappable = true
        gmsPolygon.map = gmsView
        #endif

        return polygon.id
    }

    func removePolygon(id: String) {
        polygonIds.remove(id)
        // Note: Full implementation would track GMSPolygon objects for removal
    }

    func addMarker(_ marker: MapMarker) -> String {
        markerIds.insert(marker.id)

        #if canImport(GoogleMaps)
        guard let gmsView = mapView as? GMSMapView else { return marker.id }

        let gmsMarker = GMSMarker(position: marker.coordinate)
        gmsMarker.title = marker.title
        gmsMarker.icon = marker.icon
        gmsMarker.map = gmsView
        #endif

        return marker.id
    }

    func removeMarker(id: String) {
        markerIds.remove(id)
    }

    func setUserLocationVisible(_ visible: Bool) {
        #if canImport(GoogleMaps)
        (mapView as? GMSMapView)?.isMyLocationEnabled = visible
        #endif
    }

    func setMapStyle(_ style: MapStyle) {
        #if canImport(GoogleMaps)
        guard let gmsView = mapView as? GMSMapView else { return }
        applyStyle(style, to: gmsView)
        #endif
    }

    // MARK: - Private

    #if canImport(GoogleMaps)
    private func applyStyle(_ style: MapStyle, to mapView: GMSMapView) {
        switch style {
        case .light:
            mapView.mapType = .normal
        case .dark:
            mapView.mapType = .normal
        case .satellite:
            mapView.mapType = .satellite
        }
    }
    #endif
}

// MARK: - Placeholder View (when Google Maps SDK not available)

/// Placeholder view shown when Google Maps SDK is not installed
/// Displays a simple message indicating map is unavailable
private class MapPlaceholderView: UIView {
    private let label = UILabel()

    init(configuration: MapConfiguration) {
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = UIColor.systemGray6

        label.text = "Map\n(Add Google Maps SDK)"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }
}
