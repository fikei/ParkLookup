import Foundation
import UIKit
import CoreLocation
import GoogleMaps

/// Google Maps SDK implementation of MapProviderProtocol
final class GoogleMapsAdapter: MapProviderProtocol {

    private var mapView: GMSMapView?
    private var polygons: [String: GMSPolygon] = [:]
    private var markers: [String: GMSMarker] = [:]

    var center: CLLocationCoordinate2D {
        mapView?.camera.target ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }

    var zoomLevel: Float {
        mapView?.camera.zoom ?? 15
    }

    func createMapView(configuration: MapConfiguration) -> UIView {
        let camera = GMSCameraPosition.camera(
            withTarget: configuration.initialCenter,
            zoom: configuration.initialZoom
        )

        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.isMyLocationEnabled = configuration.showsUserLocation
        mapView.settings.myLocationButton = false
        mapView.settings.scrollGestures = configuration.isUserInteractionEnabled
        mapView.settings.zoomGestures = configuration.isUserInteractionEnabled
        mapView.settings.rotateGestures = configuration.isUserInteractionEnabled
        mapView.settings.tiltGestures = false

        // Apply style
        applyStyle(configuration.style, to: mapView)

        self.mapView = mapView
        return mapView
    }

    func setCenter(_ coordinate: CLLocationCoordinate2D, animated: Bool) {
        guard let mapView = mapView else { return }

        if animated {
            mapView.animate(toLocation: coordinate)
        } else {
            mapView.camera = GMSCameraPosition.camera(
                withTarget: coordinate,
                zoom: mapView.camera.zoom
            )
        }
    }

    func setZoomLevel(_ level: Float, animated: Bool) {
        guard let mapView = mapView else { return }

        if animated {
            mapView.animate(toZoom: level)
        } else {
            mapView.camera = GMSCameraPosition.camera(
                withTarget: mapView.camera.target,
                zoom: level
            )
        }
    }

    func addPolygon(_ polygon: MapPolygon) -> String {
        guard let mapView = mapView else { return polygon.id }

        let path = GMSMutablePath()
        for coordinate in polygon.coordinates {
            path.add(coordinate)
        }

        let gmsPolygon = GMSPolygon(path: path)
        gmsPolygon.fillColor = polygon.fillColor
        gmsPolygon.strokeColor = polygon.strokeColor
        gmsPolygon.strokeWidth = polygon.strokeWidth
        gmsPolygon.isTappable = true
        gmsPolygon.map = mapView

        polygons[polygon.id] = gmsPolygon
        return polygon.id
    }

    func removePolygon(id: String) {
        polygons[id]?.map = nil
        polygons.removeValue(forKey: id)
    }

    func addMarker(_ marker: MapMarker) -> String {
        guard let mapView = mapView else { return marker.id }

        let gmsMarker = GMSMarker(position: marker.coordinate)
        gmsMarker.title = marker.title
        gmsMarker.icon = marker.icon
        gmsMarker.map = mapView

        markers[marker.id] = gmsMarker
        return marker.id
    }

    func removeMarker(id: String) {
        markers[id]?.map = nil
        markers.removeValue(forKey: id)
    }

    func setUserLocationVisible(_ visible: Bool) {
        mapView?.isMyLocationEnabled = visible
    }

    func setMapStyle(_ style: MapStyle) {
        guard let mapView = mapView else { return }
        applyStyle(style, to: mapView)
    }

    // MARK: - Private

    private func applyStyle(_ style: MapStyle, to mapView: GMSMapView) {
        switch style {
        case .light:
            mapView.mapType = .normal
            // Could apply custom JSON style here
        case .dark:
            mapView.mapType = .normal
            // Would need dark mode JSON style from Google
        case .satellite:
            mapView.mapType = .satellite
        }
    }
}
