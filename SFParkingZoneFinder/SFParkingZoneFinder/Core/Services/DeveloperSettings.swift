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

    /// Deduplication threshold for removing near-duplicate polygons (0.0 - 1.0)
    /// Polygons with overlap >= this threshold are considered duplicates
    @Published var deduplicationThreshold: Double {
        didSet { UserDefaults.standard.set(deduplicationThreshold, forKey: Keys.deduplicationThreshold) }
    }

    // MARK: - Zone Colors (hex strings without #)

    /// Color for user's valid permit zones (default: green 33B366)
    @Published var userZoneColorHex: String {
        didSet { UserDefaults.standard.set(userZoneColorHex, forKey: Keys.userZoneColorHex) }
    }

    /// Color for other RPP zones (default: orange F29933)
    @Published var rppZoneColorHex: String {
        didSet { UserDefaults.standard.set(rppZoneColorHex, forKey: Keys.rppZoneColorHex) }
    }

    /// Color for metered zones (default: grey 808080)
    @Published var meteredZoneColorHex: String {
        didSet { UserDefaults.standard.set(meteredZoneColorHex, forKey: Keys.meteredZoneColorHex) }
    }

    // MARK: - Zone Opacity

    /// Fill opacity for current zone (0.0 - 1.0)
    @Published var currentZoneFillOpacity: Double {
        didSet { UserDefaults.standard.set(currentZoneFillOpacity, forKey: Keys.currentZoneFillOpacity) }
    }

    /// Fill opacity for other zones (0.0 - 1.0)
    @Published var otherZoneFillOpacity: Double {
        didSet { UserDefaults.standard.set(otherZoneFillOpacity, forKey: Keys.otherZoneFillOpacity) }
    }

    /// Stroke opacity for current zone (0.0 - 1.0)
    @Published var currentZoneStrokeOpacity: Double {
        didSet { UserDefaults.standard.set(currentZoneStrokeOpacity, forKey: Keys.currentZoneStrokeOpacity) }
    }

    /// Stroke opacity for other zones (0.0 - 1.0)
    @Published var otherZoneStrokeOpacity: Double {
        didSet { UserDefaults.standard.set(otherZoneStrokeOpacity, forKey: Keys.otherZoneStrokeOpacity) }
    }

    // MARK: - Stroke Width

    /// Stroke width for permitted zones (user has permit) - 0.0 to 5.0
    @Published var permittedZoneStrokeWidth: Double {
        didSet { UserDefaults.standard.set(permittedZoneStrokeWidth, forKey: Keys.permittedZoneStrokeWidth) }
    }

    /// Stroke width for non-permitted zones (no permit held) - 0.0 to 5.0
    @Published var nonPermittedZoneStrokeWidth: Double {
        didSet { UserDefaults.standard.set(nonPermittedZoneStrokeWidth, forKey: Keys.nonPermittedZoneStrokeWidth) }
    }

    /// Stroke width for metered/paid zones - 0.0 to 5.0
    @Published var meteredZoneStrokeWidth: Double {
        didSet { UserDefaults.standard.set(meteredZoneStrokeWidth, forKey: Keys.meteredZoneStrokeWidth) }
    }

    // MARK: - Debug Visualization

    /// Show lookup boundaries as semi-transparent overlay
    /// Lookup uses original accurate boundaries (red outline)
    /// Display uses simplified boundaries (normal zone colors)
    @Published var showLookupBoundaries: Bool {
        didSet { UserDefaults.standard.set(showLookupBoundaries, forKey: Keys.showLookupBoundaries) }
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
        didSet { UserDefaults.standard.set(developerModeUnlocked, forKey: Keys.developerModeUnlocked) }
    }

    /// Reload trigger - increment this to force overlay reload (not persisted)
    @Published var reloadTrigger: Int = 0

    /// Force reload of map overlays
    func forceReloadOverlays() {
        reloadTrigger += 1
    }

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
        static let deduplicationThreshold = "dev.deduplicationThreshold"
        static let userZoneColorHex = "dev.userZoneColorHex"
        static let rppZoneColorHex = "dev.rppZoneColorHex"
        static let meteredZoneColorHex = "dev.meteredZoneColorHex"
        static let currentZoneFillOpacity = "dev.currentZoneFillOpacity"
        static let otherZoneFillOpacity = "dev.otherZoneFillOpacity"
        static let currentZoneStrokeOpacity = "dev.currentZoneStrokeOpacity"
        static let otherZoneStrokeOpacity = "dev.otherZoneStrokeOpacity"
        static let permittedZoneStrokeWidth = "dev.permittedZoneStrokeWidth"
        static let nonPermittedZoneStrokeWidth = "dev.nonPermittedZoneStrokeWidth"
        static let meteredZoneStrokeWidth = "dev.meteredZoneStrokeWidth"
        static let showLookupBoundaries = "dev.showLookupBoundaries"
        static let showOriginalOverlay = "dev.showOriginalOverlay"
        static let showVertexCounts = "dev.showVertexCounts"
        static let logSimplificationStats = "dev.logSimplificationStats"
        static let logLookupPerformance = "dev.logLookupPerformance"
        static let developerModeUnlocked = "dev.developerModeUnlocked"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let useConvexHull = false
        static let useDouglasPeucker = false
        static let douglasPeuckerTolerance = 0.0001  // ~11m - moderate simplification
        static let useGridSnapping = false
        static let gridSnapSize = 0.00005  // ~5.5m grid
        static let preserveCurves = true
        static let curveAngleThreshold = 15.0  // degrees - angles > 15° are "curves"
        static let cornerRoundingRadius = 0.00005  // ~5.5m radius
        static let useCornerRounding = false
        static let overlapTolerance = 0.00001  // ~1m tolerance for overlap detection
        static let useOverlapClipping = false  // Visual-only overlap clipping
        static let mergeOverlappingSameZone = false  // Merge overlapping polygons in same zone
        static let useProximityMerging = false  // Distance-based polygon merging
        static let proximityMergeDistance = 5.0  // Default 5 meters
        static let deduplicationThreshold = 0.95  // Default 95% overlap threshold
        static let userZoneColorHex = "33B366"  // Green
        static let rppZoneColorHex = "F29933"   // Orange
        static let meteredZoneColorHex = "808080"  // Grey
        static let currentZoneFillOpacity = 0.35
        static let otherZoneFillOpacity = 0.20
        static let currentZoneStrokeOpacity = 1.0
        static let otherZoneStrokeOpacity = 0.6
        static let permittedZoneStrokeWidth = 1.0
        static let nonPermittedZoneStrokeWidth = 1.0
        static let meteredZoneStrokeWidth = 1.0
        static let showLookupBoundaries = false
        static let showOriginalOverlay = false
        static let showVertexCounts = false
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
        deduplicationThreshold = defaults.object(forKey: Keys.deduplicationThreshold) as? Double ?? Defaults.deduplicationThreshold
        userZoneColorHex = defaults.object(forKey: Keys.userZoneColorHex) as? String ?? Defaults.userZoneColorHex
        rppZoneColorHex = defaults.object(forKey: Keys.rppZoneColorHex) as? String ?? Defaults.rppZoneColorHex
        meteredZoneColorHex = defaults.object(forKey: Keys.meteredZoneColorHex) as? String ?? Defaults.meteredZoneColorHex
        currentZoneFillOpacity = defaults.object(forKey: Keys.currentZoneFillOpacity) as? Double ?? Defaults.currentZoneFillOpacity
        otherZoneFillOpacity = defaults.object(forKey: Keys.otherZoneFillOpacity) as? Double ?? Defaults.otherZoneFillOpacity
        currentZoneStrokeOpacity = defaults.object(forKey: Keys.currentZoneStrokeOpacity) as? Double ?? Defaults.currentZoneStrokeOpacity
        otherZoneStrokeOpacity = defaults.object(forKey: Keys.otherZoneStrokeOpacity) as? Double ?? Defaults.otherZoneStrokeOpacity
        permittedZoneStrokeWidth = defaults.object(forKey: Keys.permittedZoneStrokeWidth) as? Double ?? Defaults.permittedZoneStrokeWidth
        nonPermittedZoneStrokeWidth = defaults.object(forKey: Keys.nonPermittedZoneStrokeWidth) as? Double ?? Defaults.nonPermittedZoneStrokeWidth
        meteredZoneStrokeWidth = defaults.object(forKey: Keys.meteredZoneStrokeWidth) as? Double ?? Defaults.meteredZoneStrokeWidth
        showLookupBoundaries = defaults.object(forKey: Keys.showLookupBoundaries) as? Bool ?? Defaults.showLookupBoundaries
        showOriginalOverlay = defaults.object(forKey: Keys.showOriginalOverlay) as? Bool ?? Defaults.showOriginalOverlay
        showVertexCounts = defaults.object(forKey: Keys.showVertexCounts) as? Bool ?? Defaults.showVertexCounts
        logSimplificationStats = defaults.object(forKey: Keys.logSimplificationStats) as? Bool ?? Defaults.logSimplificationStats
        logLookupPerformance = defaults.object(forKey: Keys.logLookupPerformance) as? Bool ?? Defaults.logLookupPerformance
        developerModeUnlocked = defaults.object(forKey: Keys.developerModeUnlocked) as? Bool ?? Defaults.developerModeUnlocked
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
        hasher.combine(userZoneColorHex)
        hasher.combine(rppZoneColorHex)
        hasher.combine(meteredZoneColorHex)
        hasher.combine(currentZoneFillOpacity)
        hasher.combine(otherZoneFillOpacity)
        hasher.combine(currentZoneStrokeOpacity)
        hasher.combine(otherZoneStrokeOpacity)
        hasher.combine(showLookupBoundaries)
        hasher.combine(showOriginalOverlay)
        hasher.combine(showVertexCounts)
        return hasher.finalize()
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
        userZoneColorHex = Defaults.userZoneColorHex
        rppZoneColorHex = Defaults.rppZoneColorHex
        meteredZoneColorHex = Defaults.meteredZoneColorHex
        currentZoneFillOpacity = Defaults.currentZoneFillOpacity
        otherZoneFillOpacity = Defaults.otherZoneFillOpacity
        currentZoneStrokeOpacity = Defaults.currentZoneStrokeOpacity
        otherZoneStrokeOpacity = Defaults.otherZoneStrokeOpacity
        showLookupBoundaries = Defaults.showLookupBoundaries
        showOriginalOverlay = Defaults.showOriginalOverlay
        showVertexCounts = Defaults.showVertexCounts
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

    /// Get user zone color from hex setting
    var userZoneColor: UIColor {
        Self.colorFromHex(userZoneColorHex)
    }

    /// Get RPP zone color from hex setting
    var rppZoneColor: UIColor {
        Self.colorFromHex(rppZoneColorHex)
    }

    /// Get metered zone color from hex setting
    var meteredZoneColor: UIColor {
        Self.colorFromHex(meteredZoneColorHex)
    }

    /// Get fill opacity based on whether zone is current
    func fillOpacity(isCurrentZone: Bool) -> CGFloat {
        CGFloat(isCurrentZone ? currentZoneFillOpacity : otherZoneFillOpacity)
    }

    /// Get stroke opacity based on whether zone is current
    func strokeOpacity(isCurrentZone: Bool) -> CGFloat {
        CGFloat(isCurrentZone ? currentZoneStrokeOpacity : otherZoneStrokeOpacity)
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
