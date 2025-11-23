import Foundation
import Combine

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

    // MARK: - Keys

    private enum Keys {
        static let useConvexHull = "dev.useConvexHull"
        static let useDouglasPeucker = "dev.useDouglasPeucker"
        static let douglasPeuckerTolerance = "dev.douglasPeuckerTolerance"
        static let useGridSnapping = "dev.useGridSnapping"
        static let gridSnapSize = "dev.gridSnapSize"
        static let preserveCurves = "dev.preserveCurves"
        static let curveAngleThreshold = "dev.curveAngleThreshold"
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
        useConvexHull || useDouglasPeucker || useGridSnapping
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
        showLookupBoundaries = Defaults.showLookupBoundaries
        showOriginalOverlay = Defaults.showOriginalOverlay
        showVertexCounts = Defaults.showVertexCounts
        logSimplificationStats = Defaults.logSimplificationStats
        logLookupPerformance = Defaults.logLookupPerformance
        // Don't reset developerModeUnlocked
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
