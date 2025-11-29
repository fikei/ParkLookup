import MapKit
import SwiftUI
import CoreLocation

/// Custom polygon that holds reference to blockface data
class BlockfacePolygon: MKPolygon {
    var blockface: Blockface?
}

/// Custom polyline for blockface centerlines (debug visualization)
class BlockfacePolyline: MKPolyline {
    var blockface: Blockface?
}

/// Custom polyline for perpendicular direction markers (debug visualization)
class PerpendicularMarker: MKPolyline {
    // Just a marker class to distinguish from centerlines
}

/// Extension to add blockface rendering to existing map views
extension MKMapView {
    /// Add blockface overlays to the map as polygons with actual width
    func addBlockfaceOverlays(_ blockfaces: [Blockface]) {
        let devSettings = DeveloperSettings.shared

        print("🔧 DEBUG: Adding \(blockfaces.count) blockface overlays")

        // Update statistics - count each category
        var noRegs = 0
        var noParking = 0
        var rpp = 0
        var timeLimit = 0

        for bf in blockfaces {
            if bf.regulations.isEmpty {
                noRegs += 1
            } else {
                var hasNoParking = false
                var hasRPP = false
                var hasTimeLimit = false

                for reg in bf.regulations {
                    if reg.type == "noParking" {
                        hasNoParking = true
                    }
                    if reg.permitZone != nil {
                        hasRPP = true
                    }
                    if reg.type == "timeLimit" {
                        hasTimeLimit = true
                    }
                }

                // Priority: No Parking > RPP > Time Limited
                if hasNoParking {
                    noParking += 1
                } else if hasRPP {
                    rpp += 1
                } else if hasTimeLimit {
                    timeLimit += 1
                }
            }
        }

        DispatchQueue.main.async {
            devSettings.totalBlockfacesLoaded = blockfaces.count
            devSettings.blockfacesWithRegulations = blockfaces.count - noRegs
            devSettings.blockfacesWithoutRegulations = noRegs
            devSettings.blockfacesNoParking = noParking
            devSettings.blockfacesRPP = rpp
            devSettings.blockfacesTimeLimit = timeLimit
        }

        for (index, blockface) in blockfaces.enumerated() {
            var centerline = blockface.geometry.locationCoordinates
            guard centerline.count >= 2 else { continue }

            if index < 3 {  // Log first 3 blockfaces for debugging
                print("🔧 DEBUG: Blockface \(index) (\(blockface.street), \(blockface.side) side)")
                print("  Original centerline points: \(centerline.count)")
                print("  Original first point: lat=\(centerline[0].latitude), lon=\(centerline[0].longitude)")
            }

            // Apply global transformations to centerline FIRST
            centerline = transformCenterline(centerline, devSettings: devSettings)

            if index < 3 {
                print("  Transformed first point: lat=\(centerline[0].latitude), lon=\(centerline[0].longitude)")
                print("  Second point: lat=\(centerline[1].latitude), lon=\(centerline[1].longitude)")
                let dlat = centerline[1].latitude - centerline[0].latitude
                let dlon = centerline[1].longitude - centerline[0].longitude
                print("  Direction: dlat=\(dlat), dlon=\(dlon)")
            }

            // Add polygons if enabled
            if devSettings.showBlockfacePolygons {
                // Use width from developer settings (adjustable via slider)
                let laneWidthDegrees = devSettings.blockfacePolygonWidth

                guard let polygonCoords = createParkingLanePolygon(
                    centerline: centerline,
                    widthDegrees: laneWidthDegrees,
                    side: blockface.side,
                    devSettings: devSettings
                ) else { continue }

                if index < 3 {
                    print("  Created polygon with \(polygonCoords.count) points")
                    print("  Width setting: \(laneWidthDegrees) degrees (TESTING: forced large)")
                }

                let polygon = BlockfacePolygon(
                    coordinates: polygonCoords,
                    count: polygonCoords.count
                )
                polygon.blockface = blockface

                if index < 3 {
                    print("  ✅ Adding polygon overlay to map")
                }
                addOverlay(polygon)
            } else if index < 3 {
                print("  ⚠️ SKIPPING polygon - showBlockfacePolygons is OFF")
            }

            // Add centerline polylines if enabled
            if devSettings.showBlockfaceCenterlines {
                let polyline = BlockfacePolyline(
                    coordinates: centerline,
                    count: centerline.count
                )
                polyline.blockface = blockface
                if index < 3 {
                    print("  ✅ Adding centerline polyline overlay to map")
                }
                addOverlay(polyline)
            } else if index < 3 {
                print("  ⚠️ SKIPPING centerline - showBlockfaceCenterlines is OFF")
            }

            // DIAGNOSTIC: Add direction arrow at start of each blockface
            if devSettings.showBlockfaceCenterlines && centerline.count >= 2 {
                let start = centerline[0]
                let next = centerline[1]
                let arrowLength = 0.00015  // Small arrow in degrees
                let dx = next.longitude - start.longitude
                let dy = next.latitude - start.latitude
                let len = sqrt(dx*dx + dy*dy)
                let endPoint = CLLocationCoordinate2D(
                    latitude: start.latitude + (dy/len) * arrowLength,
                    longitude: start.longitude + (dx/len) * arrowLength
                )
                let arrow = MKPolyline(coordinates: [start, endPoint], count: 2)
                addOverlay(arrow)
            }
        }
    }

    /// Remove all blockface overlays
    func removeBlockfaceOverlays() {
        let blockfaceOverlays = overlays.compactMap { $0 as? BlockfacePolygon }
        removeOverlays(blockfaceOverlays)
    }

    /// Calculate the bearing (compass direction) of a centerline
    /// Returns bearing in degrees (0° = North, 90° = East, 180° = South, 270° = West)
    private func calculateBearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dlon = (end.longitude - start.longitude) * .pi / 180

        let y = sin(dlon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
        let bearing = atan2(y, x) * 180 / .pi

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Calculate the angle difference between two bearings
    /// Returns the smallest angle difference in degrees (0-180)
    private func angleDifference(_ bearing1: Double, _ bearing2: Double) -> Double {
        var diff = abs(bearing1 - bearing2)
        if diff > 180 {
            diff = 360 - diff
        }
        return diff
    }

    /// Determine smart offset direction based on street bearing and side label
    /// Returns true to offset right, false to offset left (when traveling in line direction)
    ///
    /// Algorithm:
    /// 1. Determine the desired offset compass direction based on side label
    ///    - WEST/EVEN → offset EAST (90°) toward street center
    ///    - EAST/ODD → offset WEST (270°) toward street center
    ///    - NORTH → offset SOUTH (180°) toward street center
    ///    - SOUTH → offset NORTH (0°) toward street center
    /// 2. Calculate what direction the right perpendicular points based on centerline bearing
    ///    - Right perpendicular is 90° clockwise from forward direction
    /// 3. Choose right if it aligns better with desired direction, otherwise choose left
    private func shouldOffsetRight(side: String, bearing: Double) -> Bool {
        let sideUpper = side.uppercased()

        // Determine the desired offset direction (compass bearing) based on side label
        let preferredDirection: Double
        switch sideUpper {
        case "WEST", "EVEN":
            preferredDirection = 90   // offset EAST toward street center
        case "EAST", "ODD":
            preferredDirection = 270  // offset WEST toward street center
        case "NORTH":
            preferredDirection = 180  // offset SOUTH toward street center
        case "SOUTH":
            preferredDirection = 0    // offset NORTH toward street center
        case "UNKNOWN":
            // UNKNOWN: default to right for consistent rendering
            // Future enhancement: could analyze bearing and nearby blockfaces
            // to infer correct direction for unknown sides
            return true
        default:
            return true
        }

        // Calculate what direction the right perpendicular points
        // Right perpendicular is 90° clockwise from the forward direction
        let rightPerpBearing = (bearing + 90).truncatingRemainder(dividingBy: 360)
        let leftPerpBearing = (bearing - 90 + 360).truncatingRemainder(dividingBy: 360)

        // Choose the perpendicular that best aligns with the preferred direction
        let rightAlignment = angleDifference(rightPerpBearing, preferredDirection)
        let leftAlignment = angleDifference(leftPerpBearing, preferredDirection)

        return rightAlignment < leftAlignment
    }

    /// Create a polygon representing a parking lane by offsetting a centerline
    /// Uses bearing-aware perpendicular offset to always offset toward street center
    ///
    /// Algorithm:
    /// 1. Determines desired offset direction based on side label (e.g., WEST → offset EAST)
    /// 2. Calculates centerline bearing to determine which perpendicular (left/right) points in desired direction
    /// 3. Offsets each point perpendicular to the local forward direction
    /// 4. Correctly handles all centerline directions and diagonal streets
    ///
    /// - For known sides (NORTH/SOUTH/EAST/WEST/EVEN/ODD): offsets toward street center
    /// - For UNKNOWN sides: defaults to right offset for consistent rendering
    private func createParkingLanePolygon(
        centerline: [CLLocationCoordinate2D],
        widthDegrees: Double,
        side: String,
        devSettings: DeveloperSettings
    ) -> [CLLocationCoordinate2D]? {
        guard centerline.count >= 2 else { return nil }

<<<<<<< HEAD
        // Convert width from degrees to meters (approximate at SF latitude)
        // At 37.75°N: 1° latitude ≈ 111km, 1° longitude ≈ 87.7km
        // Using average for width: ~99km per degree
        let widthMeters = widthDegrees * 99_000.0

        // Determine offset direction based on side
        // The centerline is at the curb, and parking lane extends TOWARD street center
        // EVEN = right curb → offset LEFT (toward center)
        // ODD = left curb → offset RIGHT (toward center)
        // So we use OPPOSITE of the side designation
        let offsetToRight = side.uppercased() == "ODD"
=======
        // Calculate bearing for the centerline
        let bearing = calculateBearing(from: centerline.first!, to: centerline.last!)

        // Smart offset direction based on side label
        // Uses side labels when available (4% of blockfaces) to offset toward street center
        // Falls back to right offset for UNKNOWN sides (95.9% of blockfaces)
        let offsetToRight = shouldOffsetRight(side: side, bearing: bearing)

        // Get adjustment parameters from developer settings
        let lonScaleMultiplier = devSettings.blockfaceLonScaleMultiplier
        let perpendicularRotation = devSettings.blockfacePerpendicularRotation
>>>>>>> claude/fix-blockfaces-alignment-013GrQUCteA8boVU7HxdA7GU

        var offsetSide: [CLLocationCoordinate2D] = []

        // Debug logging for ALL blockfaces to help diagnose rotation issues
        let shouldDebug = true
        let devSettings = DeveloperSettings.shared

        // Convert centerline to map points (Mercator projection coordinates in meters)
        let centerlineMapPoints = centerline.map { MKMapPoint($0) }

        if shouldDebug {
            print("\n🔧 DEBUG: Perpendicular calculation")
            print("  Side: \(side) (offsetToRight=\(offsetToRight))")
            print("  Width: \(widthDegrees)° ≈ \(widthMeters)m")
            print("  First coord: lat=\(centerline[0].latitude), lon=\(centerline[0].longitude)")
            print("  First map point: x=\(centerlineMapPoints[0].x)m, y=\(centerlineMapPoints[0].y)m")
        }

        for i in 0..<centerlineMapPoints.count {
            let point = centerlineMapPoints[i]

            // Calculate perpendicular offset direction in map point space
            var perpVector: (x: Double, y: Double)

            if i == 0 {
                // First point - use direction to next point
                let next = centerlineMapPoints[i + 1]
                let forward = (x: next.x - point.x, y: next.y - point.y)

<<<<<<< HEAD
                // Calculate perpendicular in map point space (already in meters, Mercator-projected)
                // MKMapPoint: x=east (right), y=south (DOWN - inverted from normal Cartesian!)
                // For a vector pointing north (dy<0), rotating 90° clockwise should point east (dx>0)
                // Formula: 90° clockwise (RIGHT): (dx, dy) → (-dy, dx)
                // Formula: 90° counter-clockwise (LEFT): (dx, dy) → (dy, -dx)
                if offsetToRight {
                    perpVector = (x: -forward.y, y: forward.x)
                } else {
                    perpVector = (x: forward.y, y: -forward.x)
=======
                // Account for latitude/longitude scaling
                // At higher latitudes, longitude degrees are "shorter" than latitude degrees
                // 1° lon = 1° lat × cos(latitude) in ground distance
                let latRadians = point.latitude * .pi / 180
                let lonScaleFactor = cos(latRadians) * lonScaleMultiplier

                // Scale longitude to metric space where 1° lon = 1° lat in actual distance
                // Since 1° lon is shorter, we DIVIDE by cos(lat) to scale it UP
                let forwardMetric = (lat: forward.lat, lon: forward.lon / lonScaleFactor)

                // Calculate perpendicular in metric space
                // In metric space where coordinates are (lat, lon) representing (y, x):
                // 90° clockwise RIGHT turn: (y, x) → (-x, y) → (lat: -lon, lon: lat)
                // 90° counter-clockwise LEFT turn: (y, x) → (x, -y) → (lat: lon, lon: -lat)
                var perpMetric: (lat: Double, lon: Double)
                if offsetToRight {
                    perpMetric = (lat: -forwardMetric.lon, lon: forwardMetric.lat)
                } else {
                    perpMetric = (lat: forwardMetric.lon, lon: -forwardMetric.lat)
>>>>>>> claude/fix-blockfaces-alignment-013GrQUCteA8boVU7HxdA7GU
                }

                if shouldDebug && i == 0 {
                    // Calculate angles for debugging
                    let forwardAngle = atan2(forward.y, forward.x) * 180 / .pi
                    let perpAngle = atan2(perpVector.y, perpVector.x) * 180 / .pi
                    let angleDiff = perpAngle - forwardAngle

<<<<<<< HEAD
                    print("  Point 0:")
                    print("    Forward vector: dx=\(String(format: "%.2f", forward.x))m, dy=\(String(format: "%.2f", forward.y))m")
                    print("    Forward angle: \(String(format: "%.1f", forwardAngle))° (0°=east, 90°=south, -90°=north)")
                    print("    Perp vector (raw): dx=\(String(format: "%.2f", perpVector.x))m, dy=\(String(format: "%.2f", perpVector.y))m")
                    print("    Perp angle: \(String(format: "%.1f", perpAngle))°")
                    print("    Angle difference: \(String(format: "%.1f", angleDiff))° (should be ±90°)")
=======
                // Convert back to geographic space
                // perpMetric.lat came from rotating dlon (already scaled by 1/cos in metric space)
                // perpMetric.lon came from rotating dlat (in natural metric units)
                // When perpMetric.lon becomes geographic lon, dlat → dlon needs division by cos
                // because longitude degrees are shorter at this latitude
                perpVector = (lat: normalizedMetric.lat, lon: normalizedMetric.lon / lonScaleFactor)

                // Apply perpendicular rotation adjustment (if any)
                if abs(perpendicularRotation) > 0.01 {
                    perpVector = rotateVector(perpVector, degrees: perpendicularRotation)
                }

                // Apply direct adjustments if enabled
                if devSettings.blockfaceUseDirectOffset {
                    perpVector.lat *= devSettings.blockfaceDirectLatAdjust
                    perpVector.lon *= devSettings.blockfaceDirectLonAdjust
                }

                if shouldDebug {
                    print("🔧 DEBUG: Bearing-based perpendicular offset")
                    print("  Side: \(side), Bearing: \(String(format: "%.1f°", bearing))")

                    // Show the bearing-based decision
                    let sideUpper = side.uppercased()
                    switch sideUpper {
                    case "WEST", "EVEN":
                        print("  Preferred direction: EAST (90°)")
                    case "EAST", "ODD":
                        print("  Preferred direction: WEST (270°)")
                    case "NORTH":
                        print("  Preferred direction: SOUTH (180°)")
                    case "SOUTH":
                        print("  Preferred direction: NORTH (0°)")
                    default:
                        print("  Preferred direction: DEFAULT (right)")
                    }

                    let rightPerpBearing = (bearing + 90).truncatingRemainder(dividingBy: 360)
                    let leftPerpBearing = (bearing - 90 + 360).truncatingRemainder(dividingBy: 360)
                    print("  Right perp bearing: \(String(format: "%.1f°", rightPerpBearing))")
                    print("  Left perp bearing: \(String(format: "%.1f°", leftPerpBearing))")
                    print("  Selected: \(offsetToRight ? "RIGHT" : "LEFT") perpendicular")
                    print("  Latitude: \(point.latitude)°, lonScaleFactor: \(lonScaleFactor)")
                    print("  Forward vector: dlat=\(forward.lat), dlon=\(forward.lon)")

                    // Diagnose forward direction
                    let fwdDir = describeDirection(dlat: forward.lat, dlon: forward.lon)
                    print("  Forward points: \(fwdDir)")

                    print("  Forward (metric): dlat=\(forwardMetric.lat), dlon=\(forwardMetric.lon)")
                    print("  Perp (metric): dlat=\(perpMetric.lat), dlon=\(perpMetric.lon)")
                    print("  Perp (geographic): dlat=\(perpVector.lat), dlon=\(perpVector.lon)")

                    // Diagnose perpendicular direction
                    let perpDir = describeDirection(dlat: perpVector.lat, dlon: perpVector.lon)
                    print("  Perpendicular points: \(perpDir)")

                    // Determine if this is a left or right turn
                    let turn = determineTurn(forward: (forward.lat, forward.lon), perp: (perpVector.lat, perpVector.lon))
                    print("  Turn direction: \(turn) (expected: \(offsetToRight ? "RIGHT" : "LEFT"))")
>>>>>>> claude/fix-blockfaces-alignment-013GrQUCteA8boVU7HxdA7GU
                }
            } else if i == centerlineMapPoints.count - 1 {
                // Last point - use direction from previous point
                let prev = centerlineMapPoints[i - 1]
                let forward = (x: point.x - prev.x, y: point.y - prev.y)

<<<<<<< HEAD
                if offsetToRight {
                    perpVector = (x: -forward.y, y: forward.x)
                } else {
                    perpVector = (x: forward.y, y: -forward.x)
                }
=======
                // Account for latitude/longitude scaling
                let latRadians = point.latitude * .pi / 180
                let lonScaleFactor = cos(latRadians) * lonScaleMultiplier
                let forwardMetric = (lat: forward.lat, lon: forward.lon / lonScaleFactor)

                var perpMetric: (lat: Double, lon: Double)
                if offsetToRight {
                    perpMetric = (lat: -forwardMetric.lon, lon: forwardMetric.lat)
                } else {
                    perpMetric = (lat: forwardMetric.lon, lon: -forwardMetric.lat)
                }

                // Normalize in metric space
                let magnitudeMetric = sqrt(perpMetric.lat * perpMetric.lat + perpMetric.lon * perpMetric.lon)
                guard magnitudeMetric > 0 else { continue }
                let normalizedMetric = (lat: perpMetric.lat / magnitudeMetric, lon: perpMetric.lon / magnitudeMetric)

                // Convert back: perpMetric.lon came from dlat, needs 1/cos to become geographic dlon
                perpVector = (lat: normalizedMetric.lat, lon: normalizedMetric.lon / lonScaleFactor)

                // Apply perpendicular rotation adjustment (if any)
                if abs(perpendicularRotation) > 0.01 {
                    perpVector = rotateVector(perpVector, degrees: perpendicularRotation)
                }

                // Apply direct adjustments if enabled
                if devSettings.blockfaceUseDirectOffset {
                    perpVector.lat *= devSettings.blockfaceDirectLatAdjust
                    perpVector.lon *= devSettings.blockfaceDirectLonAdjust
                }
>>>>>>> claude/fix-blockfaces-alignment-013GrQUCteA8boVU7HxdA7GU
            } else {
                // Middle point - average of incoming and outgoing directions
                let prev = centerlineMapPoints[i - 1]
                let next = centerlineMapPoints[i + 1]
                let forwardIn = (x: point.x - prev.x, y: point.y - prev.y)
                let forwardOut = (x: next.x - point.x, y: next.y - point.y)
                let avgForward = (x: (forwardIn.x + forwardOut.x) / 2, y: (forwardIn.y + forwardOut.y) / 2)

<<<<<<< HEAD
                if offsetToRight {
                    perpVector = (x: -avgForward.y, y: avgForward.x)
                } else {
                    perpVector = (x: avgForward.y, y: -avgForward.x)
                }
            }

            // Normalize the perpendicular vector
            let magnitude = sqrt(perpVector.x * perpVector.x + perpVector.y * perpVector.y)
            guard magnitude > 0 else { continue }
            let normalized = (x: perpVector.x / magnitude, y: perpVector.y / magnitude)

            // Create offset point in map point space
            let offsetMapPoint = MKMapPoint(
                x: point.x + normalized.x * widthMeters,
                y: point.y + normalized.y * widthMeters
            )

            // Convert back to geographic coordinates
            let offsetCoord = offsetMapPoint.coordinate
            offsetSide.append(offsetCoord)

            if shouldDebug && i < 2 {
                print("  Point \(i) offset:")
                print("    Normalized perp: dx=\(String(format: "%.3f", normalized.x)), dy=\(String(format: "%.3f", normalized.y))")
                print("    Offset distance: \(String(format: "%.1f", widthMeters))m")
                print("    Center coord: (\(String(format: "%.6f", centerline[i].latitude)), \(String(format: "%.6f", centerline[i].longitude)))")
                print("    Offset coord: (\(String(format: "%.6f", offsetCoord.latitude)), \(String(format: "%.6f", offsetCoord.longitude)))")
                let latDiff = offsetCoord.latitude - centerline[i].latitude
                let lonDiff = offsetCoord.longitude - centerline[i].longitude
                print("    Coord delta: dlat=\(String(format: "%.8f", latDiff)), dlon=\(String(format: "%.8f", lonDiff))")
            }

            // Add visual debug markers: short perpendicular lines at each point
            if devSettings.showBlockfaceCenterlines && i < centerlineMapPoints.count {
                let debugLength = widthMeters * 0.3  // 30% of width for visibility
                let debugEndpoint = MKMapPoint(
                    x: point.x + normalized.x * debugLength,
                    y: point.y + normalized.y * debugLength
                )
                let marker = PerpendicularMarker(coordinates: [centerline[i], debugEndpoint.coordinate], count: 2)
                addOverlay(marker)
=======
                // Account for latitude/longitude scaling
                let latRadians = point.latitude * .pi / 180
                let lonScaleFactor = cos(latRadians) * lonScaleMultiplier
                let forwardMetric = (lat: avgForward.lat, lon: avgForward.lon / lonScaleFactor)

                var perpMetric: (lat: Double, lon: Double)
                if offsetToRight {
                    perpMetric = (lat: -forwardMetric.lon, lon: forwardMetric.lat)
                } else {
                    perpMetric = (lat: forwardMetric.lon, lon: -forwardMetric.lat)
                }

                // Normalize in metric space
                let magnitudeMetric = sqrt(perpMetric.lat * perpMetric.lat + perpMetric.lon * perpMetric.lon)
                guard magnitudeMetric > 0 else { continue }
                let normalizedMetric = (lat: perpMetric.lat / magnitudeMetric, lon: perpMetric.lon / magnitudeMetric)

                // Convert back: perpMetric.lon came from dlat, needs 1/cos to become geographic dlon
                perpVector = (lat: normalizedMetric.lat, lon: normalizedMetric.lon / lonScaleFactor)

                // Apply perpendicular rotation adjustment (if any)
                if abs(perpendicularRotation) > 0.01 {
                    perpVector = rotateVector(perpVector, degrees: perpendicularRotation)
                }

                // Apply direct adjustments if enabled
                if devSettings.blockfaceUseDirectOffset {
                    perpVector.lat *= devSettings.blockfaceDirectLatAdjust
                    perpVector.lon *= devSettings.blockfaceDirectLonAdjust
                }
            }

            // perpVector is already normalized from metric space calculation above
            // Create offset point by scaling the normalized perpVector by desired width
            // (Global transformations already applied to centerline)
            let offsetPoint = CLLocationCoordinate2D(
                latitude: point.latitude + perpVector.lat * widthDegrees,
                longitude: point.longitude + perpVector.lon * widthDegrees
            )

            offsetSide.append(offsetPoint)

            if shouldDebug && i < 2 {
                let dlat = offsetPoint.latitude - point.latitude
                let dlon = offsetPoint.longitude - point.longitude
                print("  Point \(i): centerline=(\(point.latitude), \(point.longitude)), offset=(\(offsetPoint.latitude), \(offsetPoint.longitude))")
                print("    Offset applied: dlat=\(dlat), dlon=\(dlon)")
>>>>>>> claude/fix-blockfaces-alignment-013GrQUCteA8boVU7HxdA7GU
            }
        }

        // Build polygon: centerline forward + offset side reversed to close the shape
        // This creates a polygon between the curb (centerline) and the street edge (offset)
        var polygonCoords = centerline
        polygonCoords.append(contentsOf: offsetSide.reversed())

        // Debug: Print all polygon vertices
        if shouldDebug {
            print("  🔷 COMPLETE POLYGON - Total vertices: " + String(polygonCoords.count))
            for (idx, coord) in polygonCoords.enumerated() {
                let label = idx < centerline.count ? "CENTER" : "OFFSET"
                print("    [\(idx)] \(label): lat=\(coord.latitude), lon=\(coord.longitude)")
            }
        }

        return polygonCoords.count >= 3 ? polygonCoords : nil
    }
}

/// Renderer for blockface polygons with actual width/dimension
class BlockfacePolygonRenderer: MKPolygonRenderer {
    let blockface: Blockface?

    init(polygon: MKPolygon, blockface: Blockface) {
        self.blockface = blockface
        super.init(polygon: polygon)

        // Configure rendering based on blockface properties
        configureStyle()
    }

    // Required initializers - not used in our implementation
    override init(overlay: MKOverlay) {
        self.blockface = nil
        super.init(overlay: overlay)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureStyle() {
<<<<<<< HEAD
        // TESTING: Force full opacity and bright color to rule out visibility issues
        let baseColor = UIColor.systemOrange
        let opacity = 1.0  // 100% opacity for testing
=======
        let devSettings = DeveloperSettings.shared

        // Color coding based on regulation type:
        // 1. No parking limits (free parking) → Green
        // 2. RPP (residential permit) → Orange
        // 3. Time Limited → Grey
        // 4. No Parking → Red
        let baseColor: UIColor
        let opacity: Double
>>>>>>> claude/fix-blockfaces-alignment-013GrQUCteA8boVU7HxdA7GU

        if let bf = blockface {
            if bf.regulations.isEmpty {
                // No restrictions = free parking → Green
                baseColor = UIColor.systemGreen
                opacity = devSettings.blockfaceOpacity
            } else {
                // Check regulation types to determine color
                var hasRPP = false
                var hasTimeLimit = false
                var hasNoParking = false

                for reg in bf.regulations {
                    if let permitZone = reg.permitZone, !permitZone.isEmpty {
                        hasRPP = true
                    }
                    if reg.type == "timeLimit" {
                        hasTimeLimit = true
                    }
                    if reg.type == "noParking" {
                        hasNoParking = true
                    }
                }

                // Priority: No Parking > RPP > Time Limited
                if hasNoParking {
                    baseColor = UIColor.systemRed
                    opacity = devSettings.blockfaceOpacity
                } else if hasRPP {
                    baseColor = UIColor.systemOrange
                    opacity = devSettings.blockfaceOpacity
                } else if hasTimeLimit {
                    baseColor = UIColor.systemGray
                    opacity = devSettings.blockfaceOpacity
                } else {
                    // Fallback for unknown regulation types
                    baseColor = UIColor.systemBlue
                    opacity = devSettings.blockfaceOpacity
                }
            }

            fillColor = baseColor.withAlphaComponent(opacity)

            // Disable stroke for thin polygons - the stroke creates visible diagonal lines
            // between centerline and offset that look wrong on the map
            strokeColor = nil
            lineWidth = 0

            // Debug: Log rendering configuration for first few polygons
            let colorName: String
            if bf.regulations.isEmpty {
                colorName = "GREEN (free parking)"
            } else {
                var types: [String] = []
                if bf.regulations.contains(where: { $0.type == "noParking" }) { types.append("No Parking→RED") }
                if bf.regulations.contains(where: { $0.permitZone != nil }) { types.append("RPP→ORANGE") }
                if bf.regulations.contains(where: { $0.type == "timeLimit" }) { types.append("Time→GREY") }
                colorName = types.joined(separator: ", ")
            }
            print("  🎨 Renderer config for \(bf.street) \(bf.side): \(colorName)")
        } else {
            // No blockface info - shouldn't happen
            baseColor = .clear
            opacity = 0.0
            fillColor = baseColor.withAlphaComponent(opacity)
            strokeColor = nil
            lineWidth = 0
        }
    }
}

/// Renderer for blockface centerline polylines (debug visualization)
class BlockfacePolylineRenderer: MKPolylineRenderer {
    let blockface: Blockface?

    init(polyline: MKPolyline, blockface: Blockface?) {
        self.blockface = blockface
        super.init(polyline: polyline)
        configureStyle()
    }

    override init(overlay: MKOverlay) {
        self.blockface = nil
        super.init(overlay: overlay)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureStyle() {
        // Simple black centerline for debugging
        strokeColor = UIColor.black.withAlphaComponent(0.7)
        lineWidth = 2
        lineDashPattern = [2, 2]  // Dashed to distinguish from polygon borders
    }
}

<<<<<<< HEAD
/// Renderer for perpendicular direction markers (debug visualization)
class PerpendicularMarkerRenderer: MKPolylineRenderer {
    override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
        configureStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureStyle() {
        // Bright red arrows showing perpendicular offset direction
        strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
        lineWidth = 3
        // Solid line to distinguish from dashed centerline
    }
}
=======
// MARK: - Diagnostic Helpers

/// Describe the compass direction of a vector
private func describeDirection(dlat: Double, dlon: Double) -> String {
    let threshold = 0.3  // Ratio threshold for "mostly" one direction
    let latAbs = abs(dlat)
    let lonAbs = abs(dlon)
    let total = latAbs + lonAbs

    if total == 0 { return "ZERO" }

    let latRatio = latAbs / total
    let lonRatio = lonAbs / total

    var parts: [String] = []

    if latRatio > threshold {
        parts.append(dlat > 0 ? "NORTH" : "SOUTH")
    }
    if lonRatio > threshold {
        parts.append(dlon > 0 ? "EAST" : "WEST")
    }

    return parts.isEmpty ? "UNCLEAR" : parts.joined(separator: "-")
}

/// Transform a centerline by applying global rotation, scale, translation, and flip
private func transformCenterline(_ centerline: [CLLocationCoordinate2D], devSettings: DeveloperSettings) -> [CLLocationCoordinate2D] {
    let flipHorizontal = devSettings.blockfaceFlipHorizontal
    let globalRotation = devSettings.blockfaceGlobalRotation
    let globalScale = devSettings.blockfaceGlobalScale
    let globalLatShift = devSettings.blockfaceGlobalLatShift
    let globalLonShift = devSettings.blockfaceGlobalLonShift

    print("🔄 transformCenterline: flip=\(flipHorizontal), rotation=\(globalRotation)°, scale=\(globalScale)x, latShift=\(globalLatShift), lonShift=\(globalLonShift)")

    // If no transformations, return original
    if !flipHorizontal && abs(globalRotation) < 0.01 && abs(globalScale - 1.0) < 0.001 && abs(globalLatShift) < 0.00001 && abs(globalLonShift) < 0.00001 {
        print("  ⏭️  No transformations needed, returning original")
        return centerline
    }

    print("  ✅ Applying transformations...")

    // Calculate centroid for rotation, scaling, and flip
    let centroidLat = centerline.map { $0.latitude }.reduce(0, +) / Double(centerline.count)
    let centroidLon = centerline.map { $0.longitude }.reduce(0, +) / Double(centerline.count)

    return centerline.map { point in
        var transformed = point

        // Apply flip, rotation, and scale around centroid if needed
        if flipHorizontal || abs(globalRotation) > 0.01 || abs(globalScale - 1.0) > 0.001 {
            // Translate to origin
            var dlat = point.latitude - centroidLat
            var dlon = point.longitude - centroidLon

            // Apply horizontal flip (mirror across vertical axis)
            if flipHorizontal {
                dlon = -dlon
            }

            // Apply rotation (lat=y, lon=x)
            if abs(globalRotation) > 0.01 {
                let radians = globalRotation * .pi / 180
                let cosTheta = cos(radians)
                let sinTheta = sin(radians)

                let rotatedLat = dlat * cosTheta - dlon * sinTheta
                let rotatedLon = dlat * sinTheta + dlon * cosTheta

                dlat = rotatedLat
                dlon = rotatedLon
            }

            // Apply scale
            let scaledLat = dlat * globalScale
            let scaledLon = dlon * globalScale

            // Translate back
            transformed.latitude = centroidLat + scaledLat
            transformed.longitude = centroidLon + scaledLon
        }

        // Apply global translation
        transformed.latitude += globalLatShift
        transformed.longitude += globalLonShift

        return transformed
    }
}

/// Determine if perpendicular is a LEFT or RIGHT turn from forward
/// Uses cross product: forward × perp > 0 → left turn, < 0 → right turn
private func determineTurn(forward: (lat: Double, lon: Double), perp: (lat: Double, lon: Double)) -> String {
    // In lat/lon space: lat=y, lon=x
    // Cross product z-component: forward.x * perp.y - forward.y * perp.x
    let cross = forward.lon * perp.lat - forward.lat * perp.lon

    if abs(cross) < 1e-10 { return "PARALLEL/OPPOSITE" }
    return cross > 0 ? "LEFT" : "RIGHT"
}

/// Rotate a vector by a given angle in degrees
/// Positive angle = clockwise rotation
private func rotateVector(_ vector: (lat: Double, lon: Double), degrees: Double) -> (lat: Double, lon: Double) {
    let radians = degrees * .pi / 180
    let cosTheta = cos(radians)
    let sinTheta = sin(radians)

    // Rotation matrix: [cos -sin; sin cos]
    // In lat/lon space: lat=y, lon=x
    return (
        lat: vector.lat * cosTheta - vector.lon * sinTheta,
        lon: vector.lat * sinTheta + vector.lon * cosTheta
    )
}
>>>>>>> claude/fix-blockfaces-alignment-013GrQUCteA8boVU7HxdA7GU
