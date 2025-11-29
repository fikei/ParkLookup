import Foundation
import Combine
import UIKit

/// Singleton managing developer/debug settings for polygon display
/// Access via hidden gesture in Settings (5-tap on version)
final class DeveloperSettings: ObservableObject {
    static let shared = DeveloperSettings()

    // MARK: - Display Simplification (affects map rendering only)

    /// Use convex hull (smoothed envelope) instead of actual boundaries
    /// Most aggressive - creates a simple outline around all zone parcels
    @Published var useConvexHull: Bool {
        didSet { UserDefaults.standard.set(useConvexHull, forKey: Keys.useConvexHull) }
    }

    /// Apply Douglas-Peucker simplification to reduce vertex count
    /// Removes points that don't significantly affect the polygon shape
    @Published var useDouglasPeucker: Bool {
        didSet { UserDefaults.standard.set(useDouglasPeucker, forKey: Keys.useDouglasPeucker) }
    }

    /// Douglas-Peucker tolerance in degrees (smaller = more detail preserved)
    /// Range: 0.00001 (~1m) to 0.001 (~110m)
    @Published var douglasPeuckerTolerance: Double {
        didSet { UserDefaults.standard.set(douglasPeuckerTolerance, forKey: Keys.douglasPeuckerTolerance) }
    }

    /// Snap vertices to a regular grid for cleaner block-aligned edges
    /// Best for straightening SF's grid streets
    @Published var useGridSnapping: Bool {
        didSet { UserDefaults.standard.set(useGridSnapping, forKey: Keys.useGridSnapping) }
    }

    /// Grid snap size in degrees (smaller = finer grid)
    /// 0.0001 ≈ 11m, 0.00005 ≈ 5.5m
    @Published var gridSnapSize: Double {
        didSet { UserDefaults.standard.set(gridSnapSize, forKey: Keys.gridSnapSize) }
    }

    // MARK: - Curve Handling

    /// Preserve curved street segments (don't over-simplify winding roads)
    /// Important for Twin Peaks, Portola, hillside areas
    @Published var preserveCurves: Bool {
        didSet { UserDefaults.standard.set(preserveCurves, forKey: Keys.preserveCurves) }
    }

    /// Angle threshold for curve detection (degrees)
    /// Segments with angle deviation > threshold are "curves" and preserved
    /// Lower = more points preserved, Higher = more aggressive simplification
    @Published var curveAngleThreshold: Double {
        didSet { UserDefaults.standard.set(curveAngleThreshold, forKey: Keys.curveAngleThreshold) }
    }

    /// Corner rounding radius in degrees
    /// Smooths sharp corners by adding arc segments
    /// 0 = no rounding, higher = more rounded corners
    @Published var cornerRoundingRadius: Double {
        didSet { UserDefaults.standard.set(cornerRoundingRadius, forKey: Keys.cornerRoundingRadius) }
    }

    /// Enable corner rounding
    @Published var useCornerRounding: Bool {
        didSet { UserDefaults.standard.set(useCornerRounding, forKey: Keys.useCornerRounding) }
    }

    /// Error tolerance for overlap detection (degrees)
    /// Used to detect and clean up small overlaps/gaps between polygons
    /// Smaller = more precise, larger = more aggressive cleanup
    @Published var overlapTolerance: Double {
        didSet { UserDefaults.standard.set(overlapTolerance, forKey: Keys.overlapTolerance) }
    }

    /// Enable overlap clipping (visual only)
    /// Clips overlapping polygons so they don't stack visually
    /// Priority: Metered > RPP, Vertical (N-S) > Horizontal (E-W)
    @Published var useOverlapClipping: Bool {
        didSet { UserDefaults.standard.set(useOverlapClipping, forKey: Keys.useOverlapClipping) }
    }

    /// Enable merging of overlapping polygons within the same permit zone
    @Published var mergeOverlappingSameZone: Bool {
        didSet { UserDefaults.standard.set(mergeOverlappingSameZone, forKey: Keys.mergeOverlappingSameZone) }
    }

    /// Enable distance-based merging of polygons within the same permit zone
    @Published var useProximityMerging: Bool {
        didSet { UserDefaults.standard.set(useProximityMerging, forKey: Keys.useProximityMerging) }
    }

    /// Distance threshold for proximity-based polygon merging (in meters)
    @Published var proximityMergeDistance: Double {
        didSet { UserDefaults.standard.set(proximityMergeDistance, forKey: Keys.proximityMergeDistance) }
    }

    /// Enable deduplication to remove near-duplicate polygons
    @Published var useDeduplication: Bool {
        didSet { UserDefaults.standard.set(useDeduplication, forKey: Keys.useDeduplication) }
    }

    /// Deduplication threshold for removing near-duplicate polygons (0.0 - 1.0)
    /// Polygons with overlap >= this threshold are considered duplicates
    @Published var deduplicationThreshold: Double {
        didSet { UserDefaults.standard.set(deduplicationThreshold, forKey: Keys.deduplicationThreshold) }
    }

    /// Enable polygon buffering to clean up self-intersecting edges
    @Published var usePolygonBuffering: Bool {
        didSet { UserDefaults.standard.set(usePolygonBuffering, forKey: Keys.usePolygonBuffering) }
    }

    /// Buffer distance for polygon cleanup (in degrees, very small values)
    /// Removes points closer than this distance to clean up geometry
    @Published var polygonBufferDistance: Double {
        didSet { UserDefaults.standard.set(polygonBufferDistance, forKey: Keys.polygonBufferDistance) }
    }

    // MARK: - In Zone (Current Zone Override)

    /// Fill opacity for current zone (user is in this zone) - 0.0 to 1.0
    /// Overrides other zone fill opacity when user is inside
    @Published var currentZoneFillOpacity: Double {
        didSet { UserDefaults.standard.set(currentZoneFillOpacity, forKey: Keys.currentZoneFillOpacity) }
    }

    /// Stroke opacity for current zone (user is in this zone) - 0.0 to 1.0
    /// Overrides other zone stroke opacity when user is inside
    @Published var currentZoneStrokeOpacity: Double {
        didSet { UserDefaults.standard.set(currentZoneStrokeOpacity, forKey: Keys.currentZoneStrokeOpacity) }
    }

    // MARK: - My Permit Zones

    /// Color for zones where user has a permit (default: green 33B366)
    @Published var myPermitZonesColorHex: String {
        didSet { UserDefaults.standard.set(myPermitZonesColorHex, forKey: Keys.myPermitZonesColorHex) }
    }

    /// Fill opacity for my permit zones (0.0 - 1.0)
    @Published var myPermitZonesFillOpacity: Double {
        didSet { UserDefaults.standard.set(myPermitZonesFillOpacity, forKey: Keys.myPermitZonesFillOpacity) }
    }

    /// Stroke opacity for my permit zones (0.0 - 1.0)
    @Published var myPermitZonesStrokeOpacity: Double {
        didSet { UserDefaults.standard.set(myPermitZonesStrokeOpacity, forKey: Keys.myPermitZonesStrokeOpacity) }
    }

    // MARK: - Free Timed Zones

    /// Color for free parking zones with time limits (RPP zones without permit) (default: orange F29933)
    @Published var freeTimedZonesColorHex: String {
        didSet { UserDefaults.standard.set(freeTimedZonesColorHex, forKey: Keys.freeTimedZonesColorHex) }
    }

    /// Fill opacity for free timed zones (0.0 - 1.0)
    @Published var freeTimedZonesFillOpacity: Double {
        didSet { UserDefaults.standard.set(freeTimedZonesFillOpacity, forKey: Keys.freeTimedZonesFillOpacity) }
    }

    /// Stroke opacity for free timed zones (0.0 - 1.0)
    @Published var freeTimedZonesStrokeOpacity: Double {
        didSet { UserDefaults.standard.set(freeTimedZonesStrokeOpacity, forKey: Keys.freeTimedZonesStrokeOpacity) }
    }

    // MARK: - Paid Zones

    /// Color for paid/metered zones (default: grey 808080)
    @Published var paidZonesColorHex: String {
        didSet { UserDefaults.standard.set(paidZonesColorHex, forKey: Keys.paidZonesColorHex) }
    }

    /// Fill opacity for paid zones (0.0 - 1.0)
    @Published var paidZonesFillOpacity: Double {
        didSet { UserDefaults.standard.set(paidZonesFillOpacity, forKey: Keys.paidZonesFillOpacity) }
    }

    /// Stroke opacity for paid zones (0.0 - 1.0)
    @Published var paidZonesStrokeOpacity: Double {
        didSet { UserDefaults.standard.set(paidZonesStrokeOpacity, forKey: Keys.paidZonesStrokeOpacity) }
    }

    // MARK: - Global Stroke Settings

    /// Global stroke width for all zones - 0.0 to 5.0
    @Published var strokeWidth: Double {
        didSet { UserDefaults.standard.set(strokeWidth, forKey: Keys.strokeWidth) }
    }

    /// Dash length for dashed lines (0 = solid line) - 0.0 to 10.0
    @Published var dashLength: Double {
        didSet { UserDefaults.standard.set(dashLength, forKey: Keys.dashLength) }
    }

    // MARK: - Debug Visualization

    /// Show lookup boundaries as semi-transparent overlay
    /// Lookup uses original accurate boundaries (red outline)
    /// Display uses simplified boundaries (normal zone colors)
    @Published var showLookupBoundaries: Bool {
        didSet { UserDefaults.standard.set(showLookupBoundaries, forKey: Keys.showLookupBoundaries) }
    }

    /// Opacity for lookup boundary overlay (0.0 - 1.0)
    @Published var lookupBoundaryOpacity: Double {
        didSet { UserDefaults.standard.set(lookupBoundaryOpacity, forKey: Keys.lookupBoundaryOpacity) }
    }

    /// Show original (unsimplified) boundaries as comparison overlay
    /// Renders with dashed outline to compare against simplified display
    @Published var showOriginalOverlay: Bool {
        didSet { UserDefaults.standard.set(showOriginalOverlay, forKey: Keys.showOriginalOverlay) }
    }

    /// Show polygon vertex count on zone labels
    /// Useful for measuring simplification effectiveness
    @Published var showVertexCounts: Bool {
        didSet { UserDefaults.standard.set(showVertexCounts, forKey: Keys.showVertexCounts) }
    }

    // MARK: - Map Overlay Visibility

    /// Show zone polygon overlays on the map
    /// When false, only shows the base map without parking zone overlays
    @Published var showZoneOverlays: Bool {
        didSet { UserDefaults.standard.set(showZoneOverlays, forKey: Keys.showZoneOverlays) }
    }

    // MARK: - Experimental Features

    /// Show blockface overlays with street cleaning visualization (PoC)
    /// Renders street segments with active/inactive street cleaning status
    @Published var showBlockfaceOverlays: Bool {
        didSet { UserDefaults.standard.set(showBlockfaceOverlays, forKey: Keys.showBlockfaceOverlays) }
    }

    /// Show blockface centerline polylines alongside blockface polygons
    /// When true, renders both the dimensional polygons and the original centerlines
    /// Useful for debugging and understanding the offset geometry
    @Published var showBlockfaceCenterlines: Bool {
        didSet { UserDefaults.standard.set(showBlockfaceCenterlines, forKey: Keys.showBlockfaceCenterlines) }
    }

    /// Show blockface polygons (dimensional parking lanes)
    @Published var showBlockfacePolygons: Bool {
        didSet { UserDefaults.standard.set(showBlockfacePolygons, forKey: Keys.showBlockfacePolygons) }
    }

    /// Show parking meters on the map
    /// Displays all parking meter locations from the Parking_Meters dataset
    /// Note: This setting is synced with the user-facing setting in SettingsViewModel
    @Published var showParkingMeters: Bool {
        didSet { UserDefaults.standard.set(showParkingMeters, forKey: "showParkingMeters") }
    }

    /// Blockface polygon stroke width
    @Published var blockfaceStrokeWidth: Double {
        didSet { UserDefaults.standard.set(blockfaceStrokeWidth, forKey: Keys.blockfaceStrokeWidth) }
    }

    /// Blockface polygon width (parking lane width in degrees)
    @Published var blockfacePolygonWidth: Double {
        didSet { UserDefaults.standard.set(blockfacePolygonWidth, forKey: Keys.blockfacePolygonWidth) }
    }

    /// Blockface polygon color (hex string)
    @Published var blockfaceColorHex: String {
        didSet { UserDefaults.standard.set(blockfaceColorHex, forKey: Keys.blockfaceColorHex) }
    }

    /// Blockface polygon opacity (0.0 - 1.0)
    @Published var blockfaceOpacity: Double {
        didSet { UserDefaults.standard.set(blockfaceOpacity, forKey: Keys.blockfaceOpacity) }
    }

    /// Blockface longitude scale multiplier (adjust cos(lat) factor for debugging)
    /// 1.0 = use standard cos(lat), <1.0 = compress, >1.0 = expand
    @Published var blockfaceLonScaleMultiplier: Double {
        didSet {
            UserDefaults.standard.set(blockfaceLonScaleMultiplier, forKey: Keys.blockfaceLonScaleMultiplier)
            forceReloadOverlays()
        }
    }

    // MARK: - Per-Block Angle Correction (affects perpendicular offset)

    /// Perpendicular rotation adjustment in degrees (fine-tune perpendicular angle for each block)
    /// Positive = rotate clockwise, Negative = rotate counter-clockwise
    /// This affects the angle of the offset from each centerline
    @Published var blockfacePerpendicularRotation: Double {
        didSet {
            print("🔧 blockfacePerpendicularRotation changed: \(oldValue)° → \(blockfacePerpendicularRotation)°")
            UserDefaults.standard.set(blockfacePerpendicularRotation, forKey: Keys.blockfacePerpendicularRotation)
            forceReloadOverlays()
            print("  → forceReloadOverlays() called, reloadTrigger now: \(reloadTrigger)")
        }
    }

    /// Use direct offset mode (bypass perpendicular calculation entirely)
    @Published var blockfaceUseDirectOffset: Bool {
        didSet {
            UserDefaults.standard.set(blockfaceUseDirectOffset, forKey: Keys.blockfaceUseDirectOffset)
            forceReloadOverlays()
        }
    }

    /// Direct latitude offset adjustment (-2.0 to 2.0, multiplies the perpendicular lat component)
    @Published var blockfaceDirectLatAdjust: Double {
        didSet {
            UserDefaults.standard.set(blockfaceDirectLatAdjust, forKey: Keys.blockfaceDirectLatAdjust)
            forceReloadOverlays()
        }
    }

    /// Direct longitude offset adjustment (-2.0 to 2.0, multiplies the perpendicular lon component)
    @Published var blockfaceDirectLonAdjust: Double {
        didSet {
            UserDefaults.standard.set(blockfaceDirectLonAdjust, forKey: Keys.blockfaceDirectLonAdjust)
            forceReloadOverlays()
        }
    }

    // MARK: - Global Transformations (affects entire plotted area)

    /// Flip entire dataset horizontally (mirror longitude coordinates)
    /// Useful when data has east/west coordinates swapped
    @Published var blockfaceFlipHorizontal: Bool {
        didSet {
            UserDefaults.standard.set(blockfaceFlipHorizontal, forKey: Keys.blockfaceFlipHorizontal)
            forceReloadOverlays()
        }
    }

    /// Global rotation of entire blockface dataset in degrees
    /// Rotates all centerlines around their collective centroid
    @Published var blockfaceGlobalRotation: Double {
        didSet {
            UserDefaults.standard.set(blockfaceGlobalRotation, forKey: Keys.blockfaceGlobalRotation)
            forceReloadOverlays()
        }
    }

    /// Global scale of entire blockface dataset
    /// Scales all centerlines from their collective centroid
    @Published var blockfaceGlobalScale: Double {
        didSet {
            UserDefaults.standard.set(blockfaceGlobalScale, forKey: Keys.blockfaceGlobalScale)
            forceReloadOverlays()
        }
    }

    /// Global latitude translation (shift all blockfaces north/south by constant amount in degrees)
    @Published var blockfaceGlobalLatShift: Double {
        didSet {
            UserDefaults.standard.set(blockfaceGlobalLatShift, forKey: Keys.blockfaceGlobalLatShift)
            forceReloadOverlays()
        }
    }

    /// Global longitude translation (shift all blockfaces east/west by constant amount in degrees)
    @Published var blockfaceGlobalLonShift: Double {
        didSet {
            UserDefaults.standard.set(blockfaceGlobalLonShift, forKey: Keys.blockfaceGlobalLonShift)
            forceReloadOverlays()
        }
    }

    /// Captured blockface calibration values (for debugging)
    @Published var capturedLonScale: Double = 1.0
    @Published var capturedRotation: Double = 0.0
    @Published var capturedWidth: Double = 0.0001
    @Published var capturedDirectLat: Double = 1.0
    @Published var capturedDirectLon: Double = 1.0
    @Published var capturedGlobalLatShift: Double = 0.0
    @Published var capturedGlobalLonShift: Double = 0.0

    /// Capture current blockface calibration values
    func captureBlockfaceCalibration() {
        capturedLonScale = blockfaceLonScaleMultiplier
        capturedRotation = blockfacePerpendicularRotation
        capturedWidth = blockfacePolygonWidth
        capturedDirectLat = blockfaceDirectLatAdjust
        capturedDirectLon = blockfaceDirectLonAdjust
        capturedGlobalLatShift = blockfaceGlobalLatShift
        capturedGlobalLonShift = blockfaceGlobalLonShift
        print("📸 CAPTURED BLOCKFACE CALIBRATION:")
        print("  Use Direct Offset: \(blockfaceUseDirectOffset)")
        print("  Polygon Width: \(capturedWidth) degrees")
        print("  ===")
        print("  TRANSFORMATIONS:")
        print("  - Longitude Scale Multiplier: \(capturedLonScale)")
        print("  - Rotation Adjustment: \(capturedRotation)°")
        print("  - Direct Lat Adjust: \(capturedDirectLat)x")
        print("  - Direct Lon Adjust: \(capturedDirectLon)x")
        print("  - Global Lat Shift: \(capturedGlobalLatShift)° (\(capturedGlobalLatShift * 111000)m)")
        print("  - Global Lon Shift: \(capturedGlobalLonShift)° (\(capturedGlobalLonShift * 85000)m at SF)")
        print("  ===")
        if blockfaceUseDirectOffset {
            print("  Code for direct offset mode:")
            print("  perpVector.lat *= \(capturedDirectLat)")
            print("  perpVector.lon *= \(capturedDirectLon)")
            print("  offsetPoint.latitude += \(capturedGlobalLatShift)")
            print("  offsetPoint.longitude += \(capturedGlobalLonShift)")
        } else {
            print("  Code for rotation mode:")
            print("  lonScaleFactor = cos(latRadians) * \(capturedLonScale)")
            print("  rotationAdjustment = \(capturedRotation)")
            print("  offsetPoint.latitude += \(capturedGlobalLatShift)")
            print("  offsetPoint.longitude += \(capturedGlobalLonShift)")
        }
    }

    // MARK: - Performance Logging

    /// Log polygon simplification stats (input/output vertex counts)
    @Published var logSimplificationStats: Bool {
        didSet { UserDefaults.standard.set(logSimplificationStats, forKey: Keys.logSimplificationStats) }
    }

    /// Log zone lookup performance timing
    @Published var logLookupPerformance: Bool {
        didSet { UserDefaults.standard.set(logLookupPerformance, forKey: Keys.logLookupPerformance) }
    }

    // MARK: - Developer Mode

    /// Whether developer settings section is unlocked
    @Published var developerModeUnlocked: Bool {
        didSet {
            print("🔧 DEBUG: developerModeUnlocked changed to: \(developerModeUnlocked)")
            UserDefaults.standard.set(developerModeUnlocked, forKey: Keys.developerModeUnlocked)
        }
    }

    /// Reload trigger - increment this to force overlay reload (not persisted)
    @Published var reloadTrigger: Int = 0

    /// Force reload of map overlays
    func forceReloadOverlays() {
        reloadTrigger += 1
    }

    // MARK: - Runtime Stats (not persisted)

    /// Total polygons currently rendered on map
    @Published var totalPolygonsRendered: Int = 0

    /// Polygons removed by overlap clipping
    @Published var polygonsRemovedByClipping: Int = 0

    /// Polygons removed by merging
    @Published var polygonsRemovedByMerging: Int = 0

    /// Polygons removed by deduplication
    @Published var polygonsRemovedByDeduplication: Int = 0

    /// Total zones loaded
    @Published var totalZonesLoaded: Int = 0

    /// Tapped overlay information (for developer debugging)
    @Published var tappedOverlayNumber: Int = 0
    @Published var tappedZoneId: String = ""
    @Published var tappedZoneCode: String = ""
    @Published var tappedIsMultiPermit: Bool = false
    @Published var tappedVertexCount: Int = 0

    /// Blockface statistics
    @Published var totalBlockfacesLoaded: Int = 0
    @Published var blockfacesWithRegulations: Int = 0
    @Published var blockfacesWithoutRegulations: Int = 0
    @Published var blockfacesNoParking: Int = 0        // Red
    @Published var blockfacesRPP: Int = 0              // Orange
    @Published var blockfacesTimeLimit: Int = 0        // Grey

    // MARK: - Keys

    private enum Keys {
        static let useConvexHull = "dev.useConvexHull"
        static let useDouglasPeucker = "dev.useDouglasPeucker"
        static let douglasPeuckerTolerance = "dev.douglasPeuckerTolerance"
        static let useGridSnapping = "dev.useGridSnapping"
        static let gridSnapSize = "dev.gridSnapSize"
        static let preserveCurves = "dev.preserveCurves"
        static let curveAngleThreshold = "dev.curveAngleThreshold"
        static let cornerRoundingRadius = "dev.cornerRoundingRadius"
        static let useCornerRounding = "dev.useCornerRounding"
        static let overlapTolerance = "dev.overlapTolerance"
        static let useOverlapClipping = "dev.useOverlapClipping"
        static let mergeOverlappingSameZone = "dev.mergeOverlappingSameZone"
        static let useProximityMerging = "dev.useProximityMerging"
        static let proximityMergeDistance = "dev.proximityMergeDistance"
        static let useDeduplication = "dev.useDeduplication"
        static let deduplicationThreshold = "dev.deduplicationThreshold"
        static let usePolygonBuffering = "dev.usePolygonBuffering"
        static let polygonBufferDistance = "dev.polygonBufferDistance"
        static let currentZoneFillOpacity = "dev.currentZoneFillOpacity"
        static let currentZoneStrokeOpacity = "dev.currentZoneStrokeOpacity"
        static let myPermitZonesColorHex = "dev.myPermitZonesColorHex"
        static let myPermitZonesFillOpacity = "dev.myPermitZonesFillOpacity"
        static let myPermitZonesStrokeOpacity = "dev.myPermitZonesStrokeOpacity"
        static let freeTimedZonesColorHex = "dev.freeTimedZonesColorHex"
        static let freeTimedZonesFillOpacity = "dev.freeTimedZonesFillOpacity"
        static let freeTimedZonesStrokeOpacity = "dev.freeTimedZonesStrokeOpacity"
        static let paidZonesColorHex = "dev.paidZonesColorHex"
        static let paidZonesFillOpacity = "dev.paidZonesFillOpacity"
        static let paidZonesStrokeOpacity = "dev.paidZonesStrokeOpacity"
        static let strokeWidth = "dev.strokeWidth"
        static let dashLength = "dev.dashLength"
        static let showLookupBoundaries = "dev.showLookupBoundaries"
        static let lookupBoundaryOpacity = "dev.lookupBoundaryOpacity"
        static let showOriginalOverlay = "dev.showOriginalOverlay"
        static let showVertexCounts = "dev.showVertexCounts"
        static let showZoneOverlays = "dev.showZoneOverlays"
        static let showBlockfaceOverlays = "dev.showBlockfaceOverlays"
        static let showBlockfaceCenterlines = "dev.showBlockfaceCenterlines"
        static let showBlockfacePolygons = "dev.showBlockfacePolygons"
        // Note: showParkingMeters uses "showParkingMeters" key (user-facing setting, not developer setting)
        static let blockfaceStrokeWidth = "dev.blockfaceStrokeWidth"
        static let blockfacePolygonWidth = "dev.blockfacePolygonWidth"
        static let blockfaceColorHex = "dev.blockfaceColorHex"
        static let blockfaceOpacity = "dev.blockfaceOpacity"
        static let blockfaceLonScaleMultiplier = "dev.blockfaceLonScaleMultiplier"
        static let blockfacePerpendicularRotation = "dev.blockfacePerpendicularRotation"
        static let blockfaceUseDirectOffset = "dev.blockfaceUseDirectOffset"
        static let blockfaceDirectLatAdjust = "dev.blockfaceDirectLatAdjust"
        static let blockfaceDirectLonAdjust = "dev.blockfaceDirectLonAdjust"
        static let blockfaceFlipHorizontal = "dev.blockfaceFlipHorizontal"
        static let blockfaceGlobalRotation = "dev.blockfaceGlobalRotation"
        static let blockfaceGlobalScale = "dev.blockfaceGlobalScale"
        static let blockfaceGlobalLatShift = "dev.blockfaceGlobalLatShift"
        static let blockfaceGlobalLonShift = "dev.blockfaceGlobalLonShift"
        static let logSimplificationStats = "dev.logSimplificationStats"
        static let logLookupPerformance = "dev.logLookupPerformance"
        static let developerModeUnlocked = "dev.developerModeUnlocked"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let useConvexHull = false
        static let useDouglasPeucker = true  // Enable D-P simplification by default
        static let douglasPeuckerTolerance = 0.0003  // ~33m - balanced simplification
        static let useGridSnapping = false
        static let gridSnapSize = 0.00005  // ~5.5m grid
        static let preserveCurves = true
        static let curveAngleThreshold = 15.0  // degrees - angles > 15° are "curves"
        static let cornerRoundingRadius = 0.00005  // ~5.5m radius
        static let useCornerRounding = true  // Enable corner rounding by default
        static let overlapTolerance = 0.00001  // ~1m tolerance for overlap detection
        static let useOverlapClipping = false  // Visual-only overlap clipping
        static let mergeOverlappingSameZone = false  // Merge overlapping polygons in same zone
        static let useProximityMerging = false  // Distance-based polygon merging
        static let proximityMergeDistance = 5.0  // Default 5 meters
        static let useDeduplication = false  // Disable deduplication by default
        static let deduplicationThreshold = 0.95  // Default 95% overlap threshold
        static let usePolygonBuffering = false  // Disabled by default (experimental)
        static let polygonBufferDistance = 0.000005  // ~0.5m default buffer distance
        static let currentZoneFillOpacity = 0.35  // In Zone fill opacity
        static let currentZoneStrokeOpacity = 1.0  // In Zone stroke opacity
        static let myPermitZonesColorHex = "33B366"  // Green
        static let myPermitZonesFillOpacity = 0.20
        static let myPermitZonesStrokeOpacity = 0.6
        static let freeTimedZonesColorHex = "F29933"  // Orange
        static let freeTimedZonesFillOpacity = 0.20
        static let freeTimedZonesStrokeOpacity = 0.6
        static let paidZonesColorHex = "808080"  // Grey
        static let paidZonesFillOpacity = 0.20
        static let paidZonesStrokeOpacity = 0.6
        static let strokeWidth = 1.0  // Global stroke width
        static let dashLength = 0.0  // 0 = solid line
        static let showLookupBoundaries = false
        static let lookupBoundaryOpacity = 0.4  // Default 40% opacity for purple overlay
        static let showOriginalOverlay = false
        static let showVertexCounts = false
        static let showZoneOverlays = true  // Show zone overlays by default
        static let showBlockfaceOverlays = true  // Enable with new GeoJSON data
        static let showBlockfaceCenterlines = true  // Show centerlines by default (main UI)
        static let showBlockfacePolygons = false  // Polygons OFF by default (available in dev overlay)
        static let showParkingMeters = false  // Parking meters OFF by default (user-facing setting)
        static let blockfaceStrokeWidth = 1.5  // Default stroke width
        static let blockfacePolygonWidth = 0.00008  // ~9.6m / 31.5 feet - increased for visibility
        static let blockfaceColorHex = "FF9500"  // Orange (SF orange)
        static let blockfaceOpacity = 0.7  // 70% opacity - increased for visibility
        static let blockfaceLonScaleMultiplier = 1.0  // Standard cos(lat) scaling
        static let blockfacePerpendicularRotation = 0.0  // No perpendicular rotation adjustment
        static let blockfaceUseDirectOffset = false  // Use perpendicular calculation by default
        static let blockfaceDirectLatAdjust = 1.0  // No adjustment
        static let blockfaceDirectLonAdjust = 1.0  // No adjustment
        static let blockfaceFlipHorizontal = false  // No horizontal flip by default
        static let blockfaceGlobalRotation = 0.0  // No global rotation
        static let blockfaceGlobalScale = 1.0  // No global scaling
        static let blockfaceGlobalLatShift = 0.0  // No global shift
        static let blockfaceGlobalLonShift = 0.0  // No global shift
        static let logSimplificationStats = false
        static let logLookupPerformance = true  // Default on for perf monitoring
        static let developerModeUnlocked = false
    }

    // MARK: - Initialization

    private init() {
        let defaults = UserDefaults.standard

        // Load persisted values or use defaults
        useConvexHull = defaults.object(forKey: Keys.useConvexHull) as? Bool ?? Defaults.useConvexHull
        useDouglasPeucker = defaults.object(forKey: Keys.useDouglasPeucker) as? Bool ?? Defaults.useDouglasPeucker
        douglasPeuckerTolerance = defaults.object(forKey: Keys.douglasPeuckerTolerance) as? Double ?? Defaults.douglasPeuckerTolerance
        useGridSnapping = defaults.object(forKey: Keys.useGridSnapping) as? Bool ?? Defaults.useGridSnapping
        gridSnapSize = defaults.object(forKey: Keys.gridSnapSize) as? Double ?? Defaults.gridSnapSize
        preserveCurves = defaults.object(forKey: Keys.preserveCurves) as? Bool ?? Defaults.preserveCurves
        curveAngleThreshold = defaults.object(forKey: Keys.curveAngleThreshold) as? Double ?? Defaults.curveAngleThreshold
        cornerRoundingRadius = defaults.object(forKey: Keys.cornerRoundingRadius) as? Double ?? Defaults.cornerRoundingRadius
        useCornerRounding = defaults.object(forKey: Keys.useCornerRounding) as? Bool ?? Defaults.useCornerRounding
        overlapTolerance = defaults.object(forKey: Keys.overlapTolerance) as? Double ?? Defaults.overlapTolerance
        useOverlapClipping = defaults.object(forKey: Keys.useOverlapClipping) as? Bool ?? Defaults.useOverlapClipping
        mergeOverlappingSameZone = defaults.object(forKey: Keys.mergeOverlappingSameZone) as? Bool ?? Defaults.mergeOverlappingSameZone
        useProximityMerging = defaults.object(forKey: Keys.useProximityMerging) as? Bool ?? Defaults.useProximityMerging
        proximityMergeDistance = defaults.object(forKey: Keys.proximityMergeDistance) as? Double ?? Defaults.proximityMergeDistance
        useDeduplication = defaults.object(forKey: Keys.useDeduplication) as? Bool ?? Defaults.useDeduplication
        deduplicationThreshold = defaults.object(forKey: Keys.deduplicationThreshold) as? Double ?? Defaults.deduplicationThreshold
        usePolygonBuffering = defaults.object(forKey: Keys.usePolygonBuffering) as? Bool ?? Defaults.usePolygonBuffering
        polygonBufferDistance = defaults.object(forKey: Keys.polygonBufferDistance) as? Double ?? Defaults.polygonBufferDistance
        currentZoneFillOpacity = defaults.object(forKey: Keys.currentZoneFillOpacity) as? Double ?? Defaults.currentZoneFillOpacity
        currentZoneStrokeOpacity = defaults.object(forKey: Keys.currentZoneStrokeOpacity) as? Double ?? Defaults.currentZoneStrokeOpacity
        myPermitZonesColorHex = defaults.object(forKey: Keys.myPermitZonesColorHex) as? String ?? Defaults.myPermitZonesColorHex
        myPermitZonesFillOpacity = defaults.object(forKey: Keys.myPermitZonesFillOpacity) as? Double ?? Defaults.myPermitZonesFillOpacity
        myPermitZonesStrokeOpacity = defaults.object(forKey: Keys.myPermitZonesStrokeOpacity) as? Double ?? Defaults.myPermitZonesStrokeOpacity
        freeTimedZonesColorHex = defaults.object(forKey: Keys.freeTimedZonesColorHex) as? String ?? Defaults.freeTimedZonesColorHex
        freeTimedZonesFillOpacity = defaults.object(forKey: Keys.freeTimedZonesFillOpacity) as? Double ?? Defaults.freeTimedZonesFillOpacity
        freeTimedZonesStrokeOpacity = defaults.object(forKey: Keys.freeTimedZonesStrokeOpacity) as? Double ?? Defaults.freeTimedZonesStrokeOpacity
        paidZonesColorHex = defaults.object(forKey: Keys.paidZonesColorHex) as? String ?? Defaults.paidZonesColorHex
        paidZonesFillOpacity = defaults.object(forKey: Keys.paidZonesFillOpacity) as? Double ?? Defaults.paidZonesFillOpacity
        paidZonesStrokeOpacity = defaults.object(forKey: Keys.paidZonesStrokeOpacity) as? Double ?? Defaults.paidZonesStrokeOpacity
        strokeWidth = defaults.object(forKey: Keys.strokeWidth) as? Double ?? Defaults.strokeWidth
        dashLength = defaults.object(forKey: Keys.dashLength) as? Double ?? Defaults.dashLength
        showLookupBoundaries = defaults.object(forKey: Keys.showLookupBoundaries) as? Bool ?? Defaults.showLookupBoundaries
        lookupBoundaryOpacity = defaults.object(forKey: Keys.lookupBoundaryOpacity) as? Double ?? Defaults.lookupBoundaryOpacity
        showOriginalOverlay = defaults.object(forKey: Keys.showOriginalOverlay) as? Bool ?? Defaults.showOriginalOverlay
        showVertexCounts = defaults.object(forKey: Keys.showVertexCounts) as? Bool ?? Defaults.showVertexCounts
        showZoneOverlays = defaults.object(forKey: Keys.showZoneOverlays) as? Bool ?? Defaults.showZoneOverlays
        showBlockfaceOverlays = defaults.object(forKey: Keys.showBlockfaceOverlays) as? Bool ?? Defaults.showBlockfaceOverlays
        showBlockfaceCenterlines = defaults.object(forKey: Keys.showBlockfaceCenterlines) as? Bool ?? Defaults.showBlockfaceCenterlines
        showBlockfacePolygons = defaults.object(forKey: Keys.showBlockfacePolygons) as? Bool ?? Defaults.showBlockfacePolygons
        showParkingMeters = defaults.object(forKey: "showParkingMeters") as? Bool ?? Defaults.showParkingMeters
        blockfaceStrokeWidth = defaults.object(forKey: Keys.blockfaceStrokeWidth) as? Double ?? Defaults.blockfaceStrokeWidth
        blockfacePolygonWidth = defaults.object(forKey: Keys.blockfacePolygonWidth) as? Double ?? Defaults.blockfacePolygonWidth
        blockfaceColorHex = defaults.object(forKey: Keys.blockfaceColorHex) as? String ?? Defaults.blockfaceColorHex
        blockfaceOpacity = defaults.object(forKey: Keys.blockfaceOpacity) as? Double ?? Defaults.blockfaceOpacity
        blockfaceLonScaleMultiplier = defaults.object(forKey: Keys.blockfaceLonScaleMultiplier) as? Double ?? Defaults.blockfaceLonScaleMultiplier
        blockfacePerpendicularRotation = defaults.object(forKey: Keys.blockfacePerpendicularRotation) as? Double ?? Defaults.blockfacePerpendicularRotation
        blockfaceUseDirectOffset = defaults.object(forKey: Keys.blockfaceUseDirectOffset) as? Bool ?? Defaults.blockfaceUseDirectOffset
        blockfaceDirectLatAdjust = defaults.object(forKey: Keys.blockfaceDirectLatAdjust) as? Double ?? Defaults.blockfaceDirectLatAdjust
        blockfaceDirectLonAdjust = defaults.object(forKey: Keys.blockfaceDirectLonAdjust) as? Double ?? Defaults.blockfaceDirectLonAdjust
        blockfaceFlipHorizontal = defaults.object(forKey: Keys.blockfaceFlipHorizontal) as? Bool ?? Defaults.blockfaceFlipHorizontal
        blockfaceGlobalRotation = defaults.object(forKey: Keys.blockfaceGlobalRotation) as? Double ?? Defaults.blockfaceGlobalRotation
        blockfaceGlobalScale = defaults.object(forKey: Keys.blockfaceGlobalScale) as? Double ?? Defaults.blockfaceGlobalScale
        blockfaceGlobalLatShift = defaults.object(forKey: Keys.blockfaceGlobalLatShift) as? Double ?? Defaults.blockfaceGlobalLatShift
        blockfaceGlobalLonShift = defaults.object(forKey: Keys.blockfaceGlobalLonShift) as? Double ?? Defaults.blockfaceGlobalLonShift
        logSimplificationStats = defaults.object(forKey: Keys.logSimplificationStats) as? Bool ?? Defaults.logSimplificationStats
        logLookupPerformance = defaults.object(forKey: Keys.logLookupPerformance) as? Bool ?? Defaults.logLookupPerformance
        developerModeUnlocked = defaults.object(forKey: Keys.developerModeUnlocked) as? Bool ?? Defaults.developerModeUnlocked

        // Reset lat/lon shift to defaults (0.0) - new GeoJSON data is correctly positioned
        if blockfaceGlobalLatShift != 0.0 || blockfaceGlobalLonShift != 0.0 {
            blockfaceGlobalLatShift = 0.0
            blockfaceGlobalLonShift = 0.0
            print("🔧 Reset blockface global shifts to 0.0 (new GeoJSON data is correctly positioned)")
        }
    }

    // MARK: - Computed Properties

    /// Whether any simplification is enabled
    var isSimplificationEnabled: Bool {
        useConvexHull || useDouglasPeucker || useGridSnapping || useCornerRounding
    }

    /// Settings hash for detecting changes (triggers map refresh)
    var settingsHash: Int {
        var hasher = Hasher()
        hasher.combine(useConvexHull)
        hasher.combine(useDouglasPeucker)
        hasher.combine(douglasPeuckerTolerance)
        hasher.combine(useGridSnapping)
        hasher.combine(gridSnapSize)
        hasher.combine(preserveCurves)
        hasher.combine(curveAngleThreshold)
        hasher.combine(useCornerRounding)
        hasher.combine(cornerRoundingRadius)
        hasher.combine(overlapTolerance)
        hasher.combine(useOverlapClipping)
        hasher.combine(mergeOverlappingSameZone)
        hasher.combine(useProximityMerging)
        hasher.combine(proximityMergeDistance)
        hasher.combine(useDeduplication)
        hasher.combine(deduplicationThreshold)
        hasher.combine(usePolygonBuffering)
        hasher.combine(polygonBufferDistance)
        hasher.combine(currentZoneFillOpacity)
        hasher.combine(currentZoneStrokeOpacity)
        hasher.combine(myPermitZonesColorHex)
        hasher.combine(myPermitZonesFillOpacity)
        hasher.combine(myPermitZonesStrokeOpacity)
        hasher.combine(freeTimedZonesColorHex)
        hasher.combine(freeTimedZonesFillOpacity)
        hasher.combine(freeTimedZonesStrokeOpacity)
        hasher.combine(paidZonesColorHex)
        hasher.combine(paidZonesFillOpacity)
        hasher.combine(paidZonesStrokeOpacity)
        hasher.combine(strokeWidth)
        hasher.combine(dashLength)
        hasher.combine(showLookupBoundaries)
        hasher.combine(lookupBoundaryOpacity)
        hasher.combine(showOriginalOverlay)
        hasher.combine(showVertexCounts)
        hasher.combine(showZoneOverlays)
        hasher.combine(showBlockfaceOverlays)
        hasher.combine(showBlockfaceCenterlines)
        hasher.combine(showBlockfacePolygons)
        hasher.combine(blockfaceStrokeWidth)
        hasher.combine(blockfacePolygonWidth)
        hasher.combine(blockfaceColorHex)
        hasher.combine(blockfaceOpacity)
        hasher.combine(blockfaceLonScaleMultiplier)
        hasher.combine(blockfacePerpendicularRotation)
        hasher.combine(blockfaceUseDirectOffset)
        hasher.combine(blockfaceDirectLatAdjust)
        hasher.combine(blockfaceDirectLonAdjust)
        hasher.combine(blockfaceFlipHorizontal)
        hasher.combine(blockfaceGlobalRotation)
        hasher.combine(blockfaceGlobalScale)
        hasher.combine(blockfaceGlobalLatShift)
        hasher.combine(blockfaceGlobalLonShift)
        return hasher.finalize()
    }

    // MARK: - UIColor Conversions

    /// UIColor for my permit zones
    var myPermitZonesColor: UIColor {
        UIColor(hex: myPermitZonesColorHex) ?? UIColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1.0)
    }

    /// UIColor for free timed zones
    var freeTimedZonesColor: UIColor {
        UIColor(hex: freeTimedZonesColorHex) ?? UIColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1.0)
    }

    /// UIColor for paid zones
    var paidZonesColor: UIColor {
        UIColor(hex: paidZonesColorHex) ?? UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    }

    /// Get a human-readable description of current simplification pipeline
    var simplificationDescription: String {
        var steps: [String] = []

        if useDouglasPeucker {
            let toleranceStr = String(format: "%.5f", douglasPeuckerTolerance)
            steps.append("D-P (\(toleranceStr)°)")
        }
        if useGridSnapping {
            let gridStr = String(format: "%.5f", gridSnapSize)
            steps.append("Grid (\(gridStr)°)")
        }
        if useCornerRounding {
            let radiusStr = String(format: "%.5f", cornerRoundingRadius)
            steps.append("Round (\(radiusStr)°)")
        }
        if useConvexHull {
            steps.append("Hull")
        }

        if steps.isEmpty {
            return "Original boundaries (no simplification)"
        }

        var desc = "Pipeline: " + steps.joined(separator: " → ")
        if preserveCurves && useDouglasPeucker {
            desc += " [curves >\(Int(curveAngleThreshold))° preserved]"
        }
        return desc
    }

    // MARK: - Actions

    /// Reset all settings to defaults
    func resetToDefaults() {
        useConvexHull = Defaults.useConvexHull
        useDouglasPeucker = Defaults.useDouglasPeucker
        douglasPeuckerTolerance = Defaults.douglasPeuckerTolerance
        useGridSnapping = Defaults.useGridSnapping
        gridSnapSize = Defaults.gridSnapSize
        preserveCurves = Defaults.preserveCurves
        curveAngleThreshold = Defaults.curveAngleThreshold
        useCornerRounding = Defaults.useCornerRounding
        cornerRoundingRadius = Defaults.cornerRoundingRadius
        overlapTolerance = Defaults.overlapTolerance
        useOverlapClipping = Defaults.useOverlapClipping
        mergeOverlappingSameZone = Defaults.mergeOverlappingSameZone
        useProximityMerging = Defaults.useProximityMerging
        proximityMergeDistance = Defaults.proximityMergeDistance
        useDeduplication = Defaults.useDeduplication
        deduplicationThreshold = Defaults.deduplicationThreshold
        usePolygonBuffering = Defaults.usePolygonBuffering
        polygonBufferDistance = Defaults.polygonBufferDistance
        currentZoneFillOpacity = Defaults.currentZoneFillOpacity
        currentZoneStrokeOpacity = Defaults.currentZoneStrokeOpacity
        myPermitZonesColorHex = Defaults.myPermitZonesColorHex
        myPermitZonesFillOpacity = Defaults.myPermitZonesFillOpacity
        myPermitZonesStrokeOpacity = Defaults.myPermitZonesStrokeOpacity
        freeTimedZonesColorHex = Defaults.freeTimedZonesColorHex
        freeTimedZonesFillOpacity = Defaults.freeTimedZonesFillOpacity
        freeTimedZonesStrokeOpacity = Defaults.freeTimedZonesStrokeOpacity
        paidZonesColorHex = Defaults.paidZonesColorHex
        paidZonesFillOpacity = Defaults.paidZonesFillOpacity
        paidZonesStrokeOpacity = Defaults.paidZonesStrokeOpacity
        strokeWidth = Defaults.strokeWidth
        dashLength = Defaults.dashLength
        showLookupBoundaries = Defaults.showLookupBoundaries
        lookupBoundaryOpacity = Defaults.lookupBoundaryOpacity
        showOriginalOverlay = Defaults.showOriginalOverlay
        showVertexCounts = Defaults.showVertexCounts
        showZoneOverlays = Defaults.showZoneOverlays
        showBlockfaceOverlays = Defaults.showBlockfaceOverlays
        showBlockfaceCenterlines = Defaults.showBlockfaceCenterlines
        showBlockfacePolygons = Defaults.showBlockfacePolygons
        blockfaceStrokeWidth = Defaults.blockfaceStrokeWidth
        blockfacePolygonWidth = Defaults.blockfacePolygonWidth
        blockfaceColorHex = Defaults.blockfaceColorHex
        blockfaceOpacity = Defaults.blockfaceOpacity
        blockfaceLonScaleMultiplier = Defaults.blockfaceLonScaleMultiplier
        blockfacePerpendicularRotation = Defaults.blockfacePerpendicularRotation
        blockfaceUseDirectOffset = Defaults.blockfaceUseDirectOffset
        blockfaceDirectLatAdjust = Defaults.blockfaceDirectLatAdjust
        blockfaceDirectLonAdjust = Defaults.blockfaceDirectLonAdjust
        blockfaceFlipHorizontal = Defaults.blockfaceFlipHorizontal
        blockfaceGlobalRotation = Defaults.blockfaceGlobalRotation
        blockfaceGlobalScale = Defaults.blockfaceGlobalScale
        blockfaceGlobalLatShift = Defaults.blockfaceGlobalLatShift
        blockfaceGlobalLonShift = Defaults.blockfaceGlobalLonShift
        logSimplificationStats = Defaults.logSimplificationStats
        logLookupPerformance = Defaults.logLookupPerformance
        // Don't reset developerModeUnlocked
    }

    // MARK: - Color Helpers

    /// Parse hex string to UIColor
    static func colorFromHex(_ hex: String) -> UIColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    // MARK: - Descriptions (for UI)

    enum SettingInfo {
        static let convexHull = "Creates smoothed envelope around zone. Most aggressive - loses all interior detail."
        static let douglasPeucker = "Removes redundant vertices while preserving shape. Good balance of simplification."
        static let gridSnapping = "Aligns vertices to grid. Best for SF's straight block edges."
        static let preserveCurves = "Prevents over-simplification of winding hillside streets."
        static let showLookupBoundaries = "Shows exact boundaries used for zone detection (red dashed)."
        static let showOriginalOverlay = "Shows unsimplified boundaries for comparison (dashed)."
        static let showVertexCounts = "Displays vertex count on zone labels to measure simplification."
    }
}
