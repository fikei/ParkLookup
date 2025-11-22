# Technical Architecture Document: SF Parking Zone Finder

**Version:** 1.0
**Last Updated:** November 2025
**Status:** Draft
**Authors:** Engineering Team

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [High-Level System Architecture](#high-level-system-architecture)
3. [Module Architecture](#module-architecture)
4. [Data Architecture](#data-architecture)
5. [API Specifications](#api-specifications)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [Open Architectural Decisions](#open-architectural-decisions)

---

## Executive Summary

SF Parking Zone Finder is an iOS application that provides instant parking zone validation for San Francisco residents. The app determines whether a user's residential parking permit is valid at their current GPS location and displays the result through a **text-first interface** with a secondary floating map.

### Key Architectural Principles

| Principle | Implementation |
|-----------|----------------|
| **Text-first UX** | Full-screen textual result is primary; map is secondary |
| **Offline-first** | All V1 functionality works without network connectivity |
| **Privacy by design** | No location data transmitted; all processing local |
| **Multi-city ready** | Architecture supports future city expansion |
| **Abstracted dependencies** | Map provider, data source, and location services are protocol-based |
| **MVVM + SwiftUI** | Modern declarative UI with clear separation of concerns |

---

## High-Level System Architecture

### System Context Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SF Parking Zone Finder                        │
│                            iOS Application                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │   SwiftUI    │    │    MVVM      │    │   Business Logic     │  │
│  │    Views     │◄──►│  ViewModels  │◄──►│      Services        │  │
│  └──────────────┘    └──────────────┘    └──────────────────────┘  │
│         │                                          │                 │
│         ▼                                          ▼                 │
│  ┌──────────────┐                        ┌──────────────────────┐  │
│  │  Google Maps │                        │    Data Layer        │  │
│  │     SDK      │                        │  (Local JSON/Cache)  │  │
│  └──────────────┘                        └──────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
         │                                          │
         ▼                                          ▼
┌─────────────────┐                      ┌─────────────────────────┐
│  Google Maps    │                      │   Future: Backend API   │
│  Tile Servers   │                      │   (See Backend.md)      │
└─────────────────┘                      └─────────────────────────┘
         │
         ▼
┌─────────────────┐
│   iOS Location  │
│    Services     │
└─────────────────┘
```

### Technology Stack

| Layer | Technology | Justification |
|-------|------------|---------------|
| **UI Framework** | SwiftUI | Modern declarative UI, native iOS feel |
| **Architecture** | MVVM | Clear separation, testability, SwiftUI compatibility |
| **Map SDK** | Google Maps SDK for iOS | Quality tiles, familiar UX, reliable geocoding |
| **Local Storage** | UserDefaults + FileManager | Simple persistence for permits and preferences |
| **Location** | CoreLocation | Native iOS location services |
| **Async** | Swift Concurrency (async/await) | Modern, readable asynchronous code |
| **Minimum iOS** | iOS 16.0+ | SwiftUI maturity, modern APIs |

### Dependency Graph

```
┌─────────────────────────────────────────────────────────────────┐
│                         App Entry Point                          │
│                      SFParkingZoneFinderApp                      │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Dependency Container                      │
│                     (Protocol-based injection)                   │
└─────────────────────────────────────────────────────────────────┘
          │              │              │              │
          ▼              ▼              ▼              ▼
    ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
    │ Location │  │   Zone   │  │  Permit  │  │   Map    │
    │ Service  │  │  Service │  │ Service  │  │ Service  │
    └──────────┘  └──────────┘  └──────────┘  └──────────┘
          │              │              │              │
          ▼              ▼              ▼              ▼
    ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
    │ CoreLoc  │  │ GeoJSON  │  │ UserDef  │  │ Google   │
    │ ation    │  │ Parser   │  │ aults    │  │ Maps SDK │
    └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

---

## Module Architecture

### Module Overview

```
SFParkingZoneFinder/
├── App/
│   ├── SFParkingZoneFinderApp.swift      # App entry point
│   ├── AppDelegate.swift                  # Google Maps SDK initialization
│   └── DependencyContainer.swift          # Service registration
│
├── Features/
│   ├── Main/                              # Primary result view
│   ├── Map/                               # Floating & full-screen map
│   ├── Onboarding/                        # First-launch flow
│   └── Settings/                          # User preferences
│
├── Core/
│   ├── Services/                          # Business logic services
│   ├── Models/                            # Data models
│   ├── Protocols/                         # Service abstractions
│   └── Extensions/                        # Swift extensions
│
├── Data/
│   ├── Local/                             # Mock data service
│   ├── Cache/                             # Caching layer
│   └── Repositories/                      # Data access layer
│
└── Resources/
    ├── sf_parking_zones.json              # Mock zone data
    └── Assets.xcassets                    # Images, colors
```

---

### Module 1: Data Loading & Caching

**Purpose:** Load, parse, and cache parking zone data from embedded JSON (V1) or remote API (future).

#### Components

```swift
// MARK: - Protocols

protocol ZoneDataSourceProtocol {
    func loadZones(for city: CityIdentifier) async throws -> [ParkingZone]
    func getDataVersion() -> String
}

protocol ZoneCacheProtocol {
    func getCachedZones(for city: CityIdentifier) -> [ParkingZone]?
    func cacheZones(_ zones: [ParkingZone], for city: CityIdentifier)
    func invalidateCache(for city: CityIdentifier)
    var lastUpdated: Date? { get }
}

// MARK: - V1 Implementation (Local JSON)

final class LocalZoneDataSource: ZoneDataSourceProtocol {
    private let bundle: Bundle
    private let jsonDecoder: JSONDecoder

    func loadZones(for city: CityIdentifier) async throws -> [ParkingZone] {
        // Load from bundled JSON file
        // Parse GeoJSON structure
        // Return array of ParkingZone models
    }
}

// MARK: - Future Implementation (Remote API)

final class RemoteZoneDataSource: ZoneDataSourceProtocol {
    private let apiClient: APIClientProtocol

    func loadZones(for city: CityIdentifier) async throws -> [ParkingZone] {
        // Fetch from backend API
        // See Backend.md for endpoint specifications
    }
}
```

#### Data Flow

```
App Launch
    │
    ▼
┌─────────────────────────────────────────┐
│         ZoneDataRepository              │
│  ┌─────────────────────────────────┐    │
│  │ 1. Check cache validity         │    │
│  │ 2. If valid → return cached     │    │
│  │ 3. If invalid → load from source│    │
│  │ 4. Parse & validate             │    │
│  │ 5. Update cache                 │    │
│  │ 6. Return zones                 │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
    │
    ▼
Zone data available for lookup
```

#### Caching Strategy (V1)

| Scenario | Behavior |
|----------|----------|
| First launch | Load from bundled JSON, cache in memory |
| Subsequent launches | Use memory cache (data is static in V1) |
| App backgrounded | Cache persists in memory for 5 minutes |
| App terminated | Reload from JSON on next launch |
| Future (with API) | TTL-based cache with background refresh |

---

### Module 2: Zone Lookup Engine

**Purpose:** Determine which parking zone(s) contain a given GPS coordinate using point-in-polygon algorithms.

#### Components

```swift
// MARK: - Protocols

protocol ZoneLookupEngineProtocol {
    func findZones(at coordinate: CLLocationCoordinate2D) -> [ParkingZone]
    func findZone(at coordinate: CLLocationCoordinate2D) -> ZoneLookupResult
}

// MARK: - Models

struct ZoneLookupResult {
    let primaryZone: ParkingZone?
    let overlappingZones: [ParkingZone]  // For boundary/overlap cases
    let confidence: LookupConfidence
    let timestamp: Date
}

enum LookupConfidence {
    case high           // Clearly within single zone
    case medium         // Near boundary, defaulting to restrictive
    case low            // Poor GPS accuracy or at exact boundary
    case outsideCoverage // Location not in any known zone
}

// MARK: - Implementation

final class ZoneLookupEngine: ZoneLookupEngineProtocol {
    private let zones: [ParkingZone]
    private let spatialIndex: SpatialIndex  // R-tree for performance

    func findZone(at coordinate: CLLocationCoordinate2D) -> ZoneLookupResult {
        // 1. Query spatial index for candidate zones
        // 2. Run point-in-polygon test for each candidate
        // 3. Handle overlapping zones (show all)
        // 4. Handle boundary cases (default to most restrictive)
        // 5. Return result with confidence level
    }
}
```

#### Point-in-Polygon Algorithm

```swift
/// Ray casting algorithm for point-in-polygon detection
func isPoint(_ point: CLLocationCoordinate2D,
             insidePolygon polygon: [CLLocationCoordinate2D]) -> Bool {
    var isInside = false
    var j = polygon.count - 1

    for i in 0..<polygon.count {
        let xi = polygon[i].longitude
        let yi = polygon[i].latitude
        let xj = polygon[j].longitude
        let yj = polygon[j].latitude

        if ((yi > point.latitude) != (yj > point.latitude)) &&
           (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi) {
            isInside.toggle()
        }
        j = i
    }
    return isInside
}
```

#### Boundary Handling (Known Risk)

> **RISK:** Zone boundary behavior requires iteration based on real-world testing.

**Current Decision:** Default to most restrictive rules when user is near a boundary.

```swift
// Boundary detection threshold (meters)
let boundaryThreshold: Double = 10.0

func handleBoundaryCase(
    zones: [ParkingZone],
    coordinate: CLLocationCoordinate2D
) -> ZoneLookupResult {
    // If multiple zones contain the point or point is within
    // boundaryThreshold of multiple zone edges:
    // 1. Include all overlapping zones in result
    // 2. Set primaryZone to most restrictive
    // 3. Set confidence to .medium
    // 4. UI will display all applicable zones

    let sortedByRestrictiveness = zones.sorted {
        $0.restrictiveness > $1.restrictiveness
    }

    return ZoneLookupResult(
        primaryZone: sortedByRestrictiveness.first,
        overlappingZones: zones,
        confidence: zones.count > 1 ? .medium : .high,
        timestamp: Date()
    )
}
```

**Mitigation Plan:**
1. Log boundary encounters in V1 (local only, for debugging)
2. Gather user feedback via "Report Issue" feature
3. Iterate algorithm based on real-world data before MVP ship

---

### Module 3: Rule Interpretation Engine

**Purpose:** Interpret parking rules and determine permit validity based on zone data and user's permits.

#### Components

```swift
// MARK: - Protocols

protocol RuleInterpreterProtocol {
    func interpretRules(
        for zone: ParkingZone,
        userPermits: [ParkingPermit],
        at time: Date
    ) -> RuleInterpretationResult
}

// MARK: - Models

struct RuleInterpretationResult {
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]  // User's permits that apply
    let ruleSummary: String                  // Human-readable summary
    let detailedRules: [ParkingRule]         // Full rule list
    let warnings: [ParkingWarning]           // Street cleaning, time limits, etc.
    let conditionalFlags: [ConditionalFlag]  // Flagged but not implemented
}

enum PermitValidityStatus {
    case valid              // Green - permit is valid
    case invalid            // Red - permit not valid here
    case conditional        // Yellow - valid with restrictions
    case noPermitRequired   // Gray - public parking
    case multipleApply      // Blue - multiple user permits valid
}

struct ConditionalFlag {
    let type: ConditionalType
    let description: String
    let requiresImplementation: Bool  // false = display only for now
}

enum ConditionalType {
    case timeOfDayRestriction
    case dayOfWeekRestriction
    case specialEventRestriction
    case temporaryRestriction
    // Add more as discovered
}

// MARK: - Implementation

final class RuleInterpreter: RuleInterpreterProtocol {

    func interpretRules(
        for zone: ParkingZone,
        userPermits: [ParkingPermit],
        at time: Date
    ) -> RuleInterpretationResult {

        // 1. Check if zone requires permits
        guard zone.requiresPermit else {
            return .noPermitRequired(zone: zone)
        }

        // 2. Find matching permits
        let matchingPermits = userPermits.filter { permit in
            zone.validPermitAreas.contains(permit.area)
        }

        // 3. Determine validity status
        let status: PermitValidityStatus
        switch matchingPermits.count {
        case 0:
            status = .invalid
        case 1:
            status = .valid
        default:
            status = .multipleApply
        }

        // 4. Flag conditional rules (not implemented, display only)
        let conditionalFlags = identifyConditionalRules(zone: zone, time: time)

        // 5. Generate human-readable summary
        let summary = generateRuleSummary(zone: zone, status: status)

        return RuleInterpretationResult(
            validityStatus: status,
            applicablePermits: matchingPermits,
            ruleSummary: summary,
            detailedRules: zone.rules,
            warnings: generateWarnings(zone: zone, time: time),
            conditionalFlags: conditionalFlags
        )
    }

    private func identifyConditionalRules(
        zone: ParkingZone,
        time: Date
    ) -> [ConditionalFlag] {
        // Flag conditions for future implementation
        // Currently: display-only, no logic enforcement
        var flags: [ConditionalFlag] = []

        if zone.hasTimeRestrictions {
            flags.append(ConditionalFlag(
                type: .timeOfDayRestriction,
                description: zone.timeRestrictionDescription,
                requiresImplementation: false  // V1: display only
            ))
        }

        return flags
    }
}
```

#### Rule Summary Generation

```swift
func generateRuleSummary(zone: ParkingZone, status: PermitValidityStatus) -> String {
    var lines: [String] = []

    // Line 1: Zone type
    lines.append(zone.displayName)

    // Line 2: Permit requirement
    if zone.requiresPermit {
        lines.append("Residential Permit Area \(zone.permitArea) only")
    }

    // Line 3: Time limits for non-permit holders
    if let timeLimit = zone.nonPermitTimeLimit {
        lines.append("\(timeLimit)-hour limit for non-permit holders")
    }

    // Line 4: Enforcement hours
    if let hours = zone.enforcementHours {
        lines.append("Enforced \(hours)")
    }

    // Line 5: Street cleaning (if applicable)
    if let cleaning = zone.streetCleaning {
        lines.append("No parking during street cleaning: \(cleaning)")
    }

    return lines.joined(separator: "\n")
}
```

---

### Module 4: Floating Map Component

**Purpose:** Provide spatial context through a minimized floating map that can expand to full-screen.

#### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MapContainerView                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              MapViewModel                            │    │
│  │  - mapState: MapState (minimized/expanded)          │    │
│  │  - userLocation: CLLocationCoordinate2D?            │    │
│  │  - visibleZones: [ParkingZone]                      │    │
│  │  - selectedZone: ParkingZone?                       │    │
│  │  - mapConfiguration: MapConfiguration               │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│            ┌──────────────┴──────────────┐                  │
│            ▼                              ▼                  │
│  ┌──────────────────┐          ┌──────────────────┐        │
│  │ MinimizedMapView │          │ ExpandedMapView  │        │
│  │   (120x120pt)    │          │  (Full Screen)   │        │
│  └──────────────────┘          └──────────────────┘        │
│            │                              │                  │
│            └──────────────┬───────────────┘                  │
│                           ▼                                  │
│              ┌──────────────────────┐                       │
│              │  GoogleMapsAdapter   │                       │
│              │  (MapProviderProto)  │                       │
│              └──────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

#### Map Provider Abstraction

```swift
// MARK: - Protocol (enables future provider switching)

protocol MapProviderProtocol {
    func createMapView(configuration: MapConfiguration) -> UIView
    func setCenter(_ coordinate: CLLocationCoordinate2D, animated: Bool)
    func setZoomLevel(_ level: Float, animated: Bool)
    func addPolygon(_ polygon: MapPolygon) -> String  // Returns polygon ID
    func removePolygon(id: String)
    func addMarker(_ marker: MapMarker) -> String
    func setUserLocationVisible(_ visible: Bool)
    func setMapStyle(_ style: MapStyle)
}

struct MapConfiguration {
    let initialCenter: CLLocationCoordinate2D
    let initialZoom: Float
    let style: MapStyle
    let isUserInteractionEnabled: Bool
    let showsUserLocation: Bool
}

enum MapStyle {
    case light
    case dark
    case satellite
}

// MARK: - Google Maps Implementation

final class GoogleMapsAdapter: MapProviderProtocol {
    private var mapView: GMSMapView?
    private var polygons: [String: GMSPolygon] = [:]
    private var markers: [String: GMSMarker] = [:]

    func createMapView(configuration: MapConfiguration) -> UIView {
        let camera = GMSCameraPosition.camera(
            withTarget: configuration.initialCenter,
            zoom: configuration.initialZoom
        )
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.isMyLocationEnabled = configuration.showsUserLocation
        mapView.settings.scrollGestures = configuration.isUserInteractionEnabled
        mapView.settings.zoomGestures = configuration.isUserInteractionEnabled
        self.mapView = mapView
        return mapView
    }

    func addPolygon(_ polygon: MapPolygon) -> String {
        let path = GMSMutablePath()
        for coordinate in polygon.coordinates {
            path.add(coordinate)
        }

        let gmsPolygon = GMSPolygon(path: path)
        gmsPolygon.fillColor = polygon.fillColor.withAlphaComponent(0.3)
        gmsPolygon.strokeColor = polygon.strokeColor
        gmsPolygon.strokeWidth = polygon.strokeWidth
        gmsPolygon.map = mapView

        let id = UUID().uuidString
        polygons[id] = gmsPolygon
        return id
    }

    // ... additional implementations
}
```

#### Minimized Map View

```swift
struct MinimizedMapView: View {
    @ObservedObject var viewModel: MapViewModel
    let onTap: () -> Void

    var body: some View {
        GoogleMapsViewRepresentable(viewModel: viewModel)
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white, lineWidth: 2)
            )
            .onTapGesture {
                onTap()
            }
            .accessibilityLabel("Map showing current parking zone")
            .accessibilityHint("Double tap to expand map")
            .accessibilityAddTraits(.isButton)
    }
}
```

#### Expanded Map View

```swift
struct ExpandedMapView: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Full-screen map
            GoogleMapsViewRepresentable(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)

            // Back button (always visible)
            Button(action: { dismiss() }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Back to Results")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .padding(.top, 60)
            .padding(.leading, 16)
            .accessibilityLabel("Back to Results")

            // Zone info card (when zone tapped)
            if let selectedZone = viewModel.selectedZone {
                ZoneInfoCard(zone: selectedZone)
                    .transition(.move(edge: .bottom))
            }

            // Legend
            MapLegendView()
                .padding(.trailing, 16)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}
```

---

### Module 5: Full-Screen Text Result View

**Purpose:** The **primary interface** displaying zone status, permit validity, and parking rules.

#### View Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                     MainResultView                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              MainResultViewModel                     │    │
│  │  - currentZoneResult: ZoneLookupResult?             │    │
│  │  - ruleInterpretation: RuleInterpretationResult?    │    │
│  │  - userPermits: [ParkingPermit]                     │    │
│  │  - isLoading: Bool                                  │    │
│  │  - error: AppError?                                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│  ┌────────────────────────┼────────────────────────────┐    │
│  │                        ▼                             │    │
│  │  ┌──────────────────────────────────────────────┐   │    │
│  │  │           ZoneStatusCardView                  │   │    │
│  │  │  - Zone name (large, prominent)              │   │    │
│  │  │  - Validity badge (color-coded)              │   │    │
│  │  └──────────────────────────────────────────────┘   │    │
│  │                        │                             │    │
│  │  ┌──────────────────────────────────────────────┐   │    │
│  │  │           RulesSummaryView                    │   │    │
│  │  │  - Bullet points of key rules                │   │    │
│  │  │  - Expandable "View Full Rules"              │   │    │
│  │  └──────────────────────────────────────────────┘   │    │
│  │                        │                             │    │
│  │  ┌──────────────────────────────────────────────┐   │    │
│  │  │        OverlappingZonesView (if applicable)   │   │    │
│  │  │  - Shows all zones when multiple apply       │   │    │
│  │  └──────────────────────────────────────────────┘   │    │
│  │                        │                             │    │
│  │  ┌──────────────────────────────────────────────┐   │    │
│  │  │           AdditionalInfoView                  │   │    │
│  │  │  - Last updated timestamp                    │   │    │
│  │  │  - Current address                           │   │    │
│  │  │  - Refresh button                            │   │    │
│  │  │  - Report Issue link                         │   │    │
│  │  └──────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │         FloatingMapWidget (overlay)                  │    │
│  │         Position: configurable (top-right default)   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

#### Main Result View Implementation

```swift
struct MainResultView: View {
    @StateObject private var viewModel: MainResultViewModel
    @State private var showExpandedMap = false
    @State private var showFullRules = false

    var body: some View {
        ZStack {
            // Primary content (scrollable)
            ScrollView {
                VStack(spacing: 24) {
                    // Zone Status Card
                    ZoneStatusCardView(
                        zoneName: viewModel.zoneName,
                        validityStatus: viewModel.validityStatus,
                        applicablePermits: viewModel.applicablePermits
                    )

                    // Overlapping Zones (if multiple)
                    if viewModel.hasOverlappingZones {
                        OverlappingZonesView(
                            zones: viewModel.overlappingZones,
                            userPermits: viewModel.userPermits
                        )
                    }

                    // Rules Summary
                    RulesSummaryView(
                        summary: viewModel.ruleSummary,
                        warnings: viewModel.warnings,
                        onViewFullRules: { showFullRules = true }
                    )

                    // Conditional Flags (display only)
                    if !viewModel.conditionalFlags.isEmpty {
                        ConditionalFlagsView(flags: viewModel.conditionalFlags)
                    }

                    // Additional Info
                    AdditionalInfoView(
                        lastUpdated: viewModel.lastUpdated,
                        address: viewModel.currentAddress,
                        onRefresh: { viewModel.refreshLocation() },
                        onReportIssue: { viewModel.reportIssue() }
                    )
                }
                .padding()
            }

            // Floating Map Widget (overlay)
            if viewModel.showFloatingMap {
                FloatingMapWidget(
                    viewModel: viewModel.mapViewModel,
                    position: viewModel.mapPosition,
                    onTap: { showExpandedMap = true }
                )
            }
        }
        .sheet(isPresented: $showExpandedMap) {
            ExpandedMapView(viewModel: viewModel.mapViewModel)
        }
        .sheet(isPresented: $showFullRules) {
            FullRulesView(rules: viewModel.detailedRules)
        }
        .navigationTitle("Parking Zone")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
            }
        }
    }
}
```

#### Zone Status Card

```swift
struct ZoneStatusCardView: View {
    let zoneName: String
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]

    var body: some View {
        VStack(spacing: 16) {
            // Zone Name (large, prominent)
            Text(zoneName)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)

            // Validity Badge
            ValidityBadgeView(
                status: validityStatus,
                permits: applicablePermits
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

struct ValidityBadgeView: View {
    let status: PermitValidityStatus
    let permits: [ParkingPermit]

    var body: some View {
        HStack(spacing: 12) {
            // Shape indicator (accessibility: not color-only)
            statusShape
                .frame(width: 24, height: 24)

            // Text
            Text(statusText)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(statusColor.opacity(0.15))
        .foregroundColor(statusColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(statusColor, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var statusColor: Color {
        switch status {
        case .valid: return .green
        case .invalid: return .red
        case .conditional: return .yellow
        case .noPermitRequired: return .gray
        case .multipleApply: return .blue
        }
    }

    private var statusShape: some View {
        // Different shapes for color-blind accessibility
        switch status {
        case .valid:
            return AnyView(Image(systemName: "checkmark.circle.fill"))
        case .invalid:
            return AnyView(Image(systemName: "xmark.circle.fill"))
        case .conditional:
            return AnyView(Image(systemName: "exclamationmark.triangle.fill"))
        case .noPermitRequired:
            return AnyView(Image(systemName: "parkingsign.circle.fill"))
        case .multipleApply:
            return AnyView(Image(systemName: "checkmark.circle.badge.checkmark.fill"))
        }
    }

    private var statusText: String {
        switch status {
        case .valid:
            return "YOUR PERMIT IS VALID HERE"
        case .invalid:
            return "YOUR PERMIT IS NOT VALID HERE"
        case .conditional:
            return "CONDITIONAL - SEE RULES BELOW"
        case .noPermitRequired:
            return "NO PERMIT REQUIRED"
        case .multipleApply:
            return "MULTIPLE PERMITS APPLY"
        }
    }
}
```

#### Overlapping Zones Display

```swift
struct OverlappingZonesView: View {
    let zones: [ParkingZone]
    let userPermits: [ParkingPermit]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Multiple Zones Apply")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(zones, id: \.id) { zone in
                HStack {
                    Text(zone.displayName)
                        .font(.body)

                    Spacer()

                    // Show validity for each zone
                    let isValid = userPermits.contains {
                        zone.validPermitAreas.contains($0.area)
                    }
                    Image(systemName: isValid ? "checkmark.circle" : "xmark.circle")
                        .foregroundColor(isValid ? .green : .red)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }

            Text("Showing most restrictive rules above")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}
```

---

### Module 6: Onboarding Flow

**Purpose:** Guide first-time users through location permissions and permit setup.

#### Flow Diagram

```
┌──────────────────┐
│  WelcomeScreen   │
│  "Get Started"   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌──────────────────┐
│ LocationPermis-  │────►│  PermitSetup     │
│ sionScreen       │     │  (If "Yes")      │
└────────┬─────────┘     └────────┬─────────┘
         │                        │
         │ (If denied)            │
         ▼                        │
┌──────────────────┐              │
│ ManualLocation   │              │
│ FallbackNote     │              │
└────────┬─────────┘              │
         │                        │
         └────────────┬───────────┘
                      ▼
         ┌──────────────────┐
         │  TutorialOverlay │
         │  (Optional)      │
         └────────┬─────────┘
                  │
                  ▼
         ┌──────────────────┐
         │   MainResultView │
         └──────────────────┘
```

#### Permit Collection

```swift
struct PermitSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("What parking permits do you have?")
                .font(.title2)
                .fontWeight(.bold)

            Text("Select all that apply")
                .foregroundColor(.secondary)

            // Permit type selector (extensible for future types)
            PermitTypePicker(
                selectedType: $viewModel.selectedPermitType
            )

            // Area selector (shown for RPP permits)
            if viewModel.selectedPermitType == .residential {
                PermitAreaGrid(
                    selectedAreas: $viewModel.selectedPermitAreas,
                    availableAreas: viewModel.availablePermitAreas
                )
            }

            // Future: Commercial, Disabled, Visitor permit types
            // UI space reserved, implementation deferred

            Spacer()

            Button("Continue") {
                viewModel.savePermits()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedPermitAreas.isEmpty)

            Button("Skip for now") {
                viewModel.skipPermitSetup()
            }
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct PermitTypePicker: View {
    @Binding var selectedType: PermitType

    var body: some View {
        VStack(spacing: 12) {
            PermitTypeButton(
                type: .residential,
                title: "Residential Permit (RPP)",
                subtitle: "For SF residents in permit areas",
                isSelected: selectedType == .residential,
                action: { selectedType = .residential }
            )

            // Future permit types - visible but disabled
            PermitTypeButton(
                type: .commercial,
                title: "Commercial Vehicle",
                subtitle: "Coming soon",
                isSelected: false,
                isDisabled: true,
                action: { }
            )

            PermitTypeButton(
                type: .disabled,
                title: "Disabled Placard",
                subtitle: "Coming soon",
                isSelected: false,
                isDisabled: true,
                action: { }
            )
        }
    }
}
```

---

### Module 7: Settings Screens

**Purpose:** Allow users to manage permits, preferences, and app information.

#### Settings Structure

```swift
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            // My Permits Section
            Section("My Permits") {
                NavigationLink(destination: PermitManagementView()) {
                    SettingsRow(
                        icon: "car.fill",
                        title: "Manage Permits",
                        subtitle: "\(viewModel.permitCount) permit(s)"
                    )
                }
            }

            // Map Preferences Section
            Section("Map Preferences") {
                Toggle("Show Floating Map", isOn: $viewModel.showFloatingMap)

                Picker("Map Position", selection: $viewModel.floatingMapPosition) {
                    Text("Top Right").tag(MapPosition.topRight)
                    Text("Top Left").tag(MapPosition.topLeft)
                    Text("Bottom Right").tag(MapPosition.bottomRight)
                }

                Picker("Map Style", selection: $viewModel.mapStyle) {
                    Text("Light").tag(MapStyle.light)
                    Text("Dark").tag(MapStyle.dark)
                    Text("Satellite").tag(MapStyle.satellite)
                }
            }

            // Future: Notifications Section (disabled)
            Section("Notifications") {
                SettingsRow(
                    icon: "bell.fill",
                    title: "Street Cleaning Alerts",
                    subtitle: "Coming in a future update"
                )
                .foregroundColor(.secondary)
            }

            // About Section
            Section("About") {
                SettingsRow(
                    icon: "info.circle",
                    title: "App Version",
                    subtitle: viewModel.appVersion
                )

                SettingsRow(
                    icon: "doc.text",
                    title: "Data Version",
                    subtitle: viewModel.dataVersion
                )

                NavigationLink(destination: PrivacyPolicyView()) {
                    SettingsRow(icon: "lock.shield", title: "Privacy Policy")
                }

                NavigationLink(destination: LicensesView()) {
                    SettingsRow(icon: "doc.plaintext", title: "Open Source Licenses")
                }
            }

            // Help Section
            Section("Help & Feedback") {
                NavigationLink(destination: FAQView()) {
                    SettingsRow(icon: "questionmark.circle", title: "FAQ")
                }

                Button(action: viewModel.reportIssue) {
                    SettingsRow(icon: "exclamationmark.bubble", title: "Report Incorrect Data")
                }

                Button(action: viewModel.rateApp) {
                    SettingsRow(icon: "star", title: "Rate on App Store")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
```

---

### Module 8: Location & Reverse Geocoding Services

**Purpose:** Acquire device location and convert coordinates to human-readable addresses.

#### Location Service

```swift
// MARK: - Protocol

protocol LocationServiceProtocol {
    var currentLocation: CLLocation? { get }
    var locationPublisher: AnyPublisher<CLLocation, Never> { get }
    var authorizationStatus: CLAuthorizationStatus { get }

    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func requestSingleLocation() async throws -> CLLocation
}

// MARK: - Implementation

final class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let locationSubject = PassthroughSubject<CLLocation, Never>()

    var currentLocation: CLLocation?
    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update when moved 10 meters
    }

    func requestSingleLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            // Request single location update
            // Handle timeout after 10 seconds
            // Return location or throw error
        }
    }

    // CLLocationManagerDelegate methods...
}
```

#### Reverse Geocoding Service

```swift
// MARK: - Protocol

protocol ReverseGeocodingServiceProtocol {
    func reverseGeocode(location: CLLocation) async throws -> Address
}

// MARK: - Implementation

final class ReverseGeocodingService: ReverseGeocodingServiceProtocol {
    private let geocoder = CLGeocoder()
    private var cache: [String: Address] = [:]

    func reverseGeocode(location: CLLocation) async throws -> Address {
        // Check cache first (key: lat,lon rounded to 5 decimals)
        let cacheKey = "\(round(location.coordinate.latitude * 100000))" +
                       ",\(round(location.coordinate.longitude * 100000))"

        if let cached = cache[cacheKey] {
            return cached
        }

        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else {
            throw GeocodingError.noResults
        }

        let address = Address(
            streetNumber: placemark.subThoroughfare,
            streetName: placemark.thoroughfare,
            neighborhood: placemark.subLocality,
            city: placemark.locality,
            formattedAddress: formatAddress(placemark)
        )

        cache[cacheKey] = address
        return address
    }
}
```

---

## Data Architecture

### Data Models

```swift
// MARK: - City Identifier (Multi-city support)

struct CityIdentifier: Codable, Hashable {
    let code: String      // "sf", "oak", "sj"
    let name: String      // "San Francisco"
    let state: String     // "CA"

    static let sanFrancisco = CityIdentifier(
        code: "sf",
        name: "San Francisco",
        state: "CA"
    )
}

// MARK: - Parking Zone

struct ParkingZone: Codable, Identifiable {
    let id: String
    let cityCode: String
    let displayName: String           // "Area Q", "2-Hour Metered Zone"
    let zoneType: ZoneType
    let permitArea: String?           // "Q", "R", nil for non-permit zones
    let validPermitAreas: [String]    // Permits valid in this zone
    let boundary: [Coordinate]        // Polygon coordinates
    let rules: [ParkingRule]
    let requiresPermit: Bool
    let restrictiveness: Int          // 1-10 scale for boundary priority
    let metadata: ZoneMetadata
}

struct Coordinate: Codable {
    let latitude: Double
    let longitude: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum ZoneType: String, Codable {
    case residentialPermit = "rpp"
    case metered = "metered"
    case timeLimited = "time_limited"
    case noParking = "no_parking"
    case towAway = "tow_away"
    case mixed = "mixed"              // Multiple rule types
}

struct ZoneMetadata: Codable {
    let dataSource: String            // "mock_v1", "datasf", "sfmta"
    let lastUpdated: Date
    let accuracy: DataAccuracy
}

enum DataAccuracy: String, Codable {
    case high       // Official source, verified
    case medium     // Official source, simplified boundaries
    case low        // Approximated or crowd-sourced
}

// MARK: - Parking Rules

struct ParkingRule: Codable, Identifiable {
    let id: String
    let ruleType: RuleType
    let description: String
    let enforcementDays: [DayOfWeek]?
    let enforcementStartTime: TimeOfDay?
    let enforcementEndTime: TimeOfDay?
    let timeLimit: Int?               // Minutes, nil if no limit
    let meterRate: Decimal?           // Dollars per hour
    let specialConditions: String?
}

enum RuleType: String, Codable {
    case permitRequired = "permit_required"
    case timeLimit = "time_limit"
    case metered = "metered"
    case streetCleaning = "street_cleaning"
    case towAway = "tow_away"
    case noParking = "no_parking"
    case loadingZone = "loading_zone"
}

struct TimeOfDay: Codable {
    let hour: Int     // 0-23
    let minute: Int   // 0-59
}

enum DayOfWeek: String, Codable, CaseIterable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday
}

// MARK: - User Permits

struct ParkingPermit: Codable, Identifiable, Hashable {
    let id: UUID
    let type: PermitType
    let area: String                  // "Q", "R", etc.
    let cityCode: String              // "sf"
    let expirationDate: Date?
    let isPrimary: Bool
    let createdAt: Date
}

enum PermitType: String, Codable {
    case residential = "rpp"
    case commercial = "commercial"
    case disabled = "disabled"
    case visitor = "visitor"
    // Extensible for future types
}

// MARK: - Address

struct Address: Codable {
    let streetNumber: String?
    let streetName: String?
    let neighborhood: String?
    let city: String?
    let formattedAddress: String
}
```

### Mock Data Schema (GeoJSON)

**File:** `Resources/sf_parking_zones.json`

```json
{
  "version": "1.0.0",
  "generatedAt": "2025-11-01T00:00:00Z",
  "city": {
    "code": "sf",
    "name": "San Francisco",
    "state": "CA",
    "bounds": {
      "north": 37.8324,
      "south": 37.6398,
      "east": -122.3281,
      "west": -122.5274
    }
  },
  "permitAreas": [
    {
      "code": "A",
      "name": "Area A",
      "neighborhoods": ["Telegraph Hill", "North Beach"]
    },
    {
      "code": "Q",
      "name": "Area Q",
      "neighborhoods": ["Castro", "Noe Valley"]
    }
  ],
  "zones": [
    {
      "id": "sf_rpp_q_001",
      "cityCode": "sf",
      "displayName": "Area Q",
      "zoneType": "rpp",
      "permitArea": "Q",
      "validPermitAreas": ["Q"],
      "requiresPermit": true,
      "restrictiveness": 8,
      "boundary": {
        "type": "Polygon",
        "coordinates": [
          [
            [-122.4359, 37.7599],
            [-122.4340, 37.7612],
            [-122.4301, 37.7598],
            [-122.4320, 37.7585],
            [-122.4359, 37.7599]
          ]
        ]
      },
      "rules": [
        {
          "id": "rule_001",
          "ruleType": "permit_required",
          "description": "Residential Permit Area Q only",
          "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
          "enforcementStartTime": { "hour": 8, "minute": 0 },
          "enforcementEndTime": { "hour": 18, "minute": 0 },
          "timeLimit": 120,
          "specialConditions": "2-hour limit for non-permit holders"
        },
        {
          "id": "rule_002",
          "ruleType": "street_cleaning",
          "description": "No parking during street cleaning",
          "enforcementDays": ["wednesday"],
          "enforcementStartTime": { "hour": 8, "minute": 0 },
          "enforcementEndTime": { "hour": 10, "minute": 0 },
          "specialConditions": "Tow-away enforced"
        }
      ],
      "metadata": {
        "dataSource": "mock_v1",
        "lastUpdated": "2025-11-01T00:00:00Z",
        "accuracy": "medium"
      }
    }
  ]
}
```

### Data Sources Reference

| Source | URL | Data Available | V1 Usage |
|--------|-----|----------------|----------|
| **DataSF** | data.sfgov.org | Parking meters, RPP areas, street segments | Schema reference |
| **SFMTA** | sfmta.com | Official RPP boundaries, meter pricing | Schema reference |
| **OpenStreetMap** | openstreetmap.org | Street geometry | Map tiles via Google |

---

## API Specifications

### V1: Local Data Interface

```swift
// Internal service interface (no network in V1)

protocol ZoneServiceProtocol {
    func getZones(for city: CityIdentifier) async throws -> [ParkingZone]
    func findZone(at coordinate: CLLocationCoordinate2D) async throws -> ZoneLookupResult
    func getDataVersion() -> String
}
```

### Future: Backend API (See Backend.md)

**Base URL:** `https://api.sfparkingzone.app/v1`

#### Endpoints (Planned)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/cities` | GET | List supported cities |
| `/cities/{code}/zones` | GET | Get all zones for a city |
| `/lookup` | POST | Find zone for coordinates |
| `/zones/{id}` | GET | Get single zone details |
| `/health` | GET | API health check |

#### Example Request/Response

```http
POST /v1/lookup
Content-Type: application/json

{
  "latitude": 37.7599,
  "longitude": -122.4359,
  "cityCode": "sf"
}
```

```json
{
  "success": true,
  "result": {
    "primaryZone": {
      "id": "sf_rpp_q_001",
      "displayName": "Area Q",
      "zoneType": "rpp"
    },
    "overlappingZones": [],
    "confidence": "high",
    "timestamp": "2025-11-21T10:30:00Z"
  }
}
```

---

## Non-Functional Requirements

### Performance Goals

| Metric | Target | Measurement |
|--------|--------|-------------|
| App cold start | < 2 seconds | Time to first meaningful paint |
| App warm start | < 1 second | Time to interactive |
| Location acquisition | < 2 seconds | GPS fix to coordinate |
| Zone lookup | < 500ms | Coordinate to result display |
| Map render (minimized) | < 200ms | First tile visible |
| Map render (expanded) | < 500ms | Full map interactive |
| Memory footprint | < 100 MB | Typical usage |
| Battery impact | Minimal | < 5% per hour active use |

#### Performance Optimization Strategies

1. **Spatial indexing:** R-tree for zone polygon lookups
2. **Lazy loading:** Load zone details on demand
3. **Image caching:** Cache map tiles via Google Maps SDK
4. **Background processing:** Parse JSON off main thread
5. **Memory management:** Release expanded map view when dismissed

### Accessibility Requirements

| Requirement | Implementation |
|-------------|----------------|
| **VoiceOver** | All interactive elements labeled; logical reading order |
| **Dynamic Type** | All text scales with system settings (minimum to AX5) |
| **High Contrast** | Compatible with Increase Contrast setting |
| **Color Independence** | Status uses shapes + text, not color alone |
| **Reduce Motion** | Animations respect system preference |
| **Voice Control** | All actions achievable via voice |
| **Minimum Touch Target** | 44x44 points for all tappable elements |

#### Accessibility Implementation

```swift
// Example: Validity badge with full accessibility
ValidityBadgeView(status: .valid)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Permit status: Valid")
    .accessibilityValue("Your Area Q permit is valid at this location")
    .accessibilityHint("Shows whether your parking permit allows parking here")
```

### Offline-First Behavior

| Scenario | Behavior |
|----------|----------|
| No network (V1) | Fully functional - all data embedded |
| Location unavailable | Show last known location (cached 5 min) |
| Poor GPS accuracy | Show accuracy indicator, use best available |
| App backgrounded | Pause location updates, preserve state |
| App terminated | Reload state from UserDefaults on next launch |

### Privacy Requirements

| Data Type | Storage | Transmission |
|-----------|---------|--------------|
| GPS coordinates | Memory only (not persisted) | Never transmitted (V1) |
| User permits | Local UserDefaults (encrypted) | Never transmitted (V1) |
| Preferences | Local UserDefaults | Never transmitted |
| Analytics | None collected (V1) | None |
| Crash reports | Apple default only | To Apple (if user opted in) |

#### Privacy Implementation

```swift
// No analytics, no tracking
// Location used only for zone lookup, never stored or transmitted

final class PrivacyManager {
    static func ensurePrivacyCompliance() {
        // Verify no analytics SDKs initialized
        // Confirm location data not persisted
        // Log privacy mode for debugging
    }
}
```

### Maintainability

| Practice | Implementation |
|----------|----------------|
| **Architecture** | MVVM with protocol-based services |
| **Dependency Injection** | All services injected via container |
| **Testing** | Protocol mocks for all services |
| **Documentation** | Inline documentation for public APIs |
| **Code Coverage Target** | >80% for business logic |
| **Linting** | SwiftLint with strict rules |
| **Formatting** | SwiftFormat for consistency |

---

## Open Architectural Decisions

### Decided

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Map Provider | Google Maps SDK | Quality, reliability, familiar UX |
| UI Framework | SwiftUI | Modern, declarative, rapid development |
| Architecture | MVVM | SwiftUI compatibility, testability |
| Local Storage | UserDefaults | Simple, sufficient for V1 data |
| Boundary Handling | Default to restrictive | User safety; iterate based on feedback |

### Open / Deferred

| Decision | Options | Status | Notes |
|----------|---------|--------|-------|
| CI/CD Pipeline | GitHub Actions, Xcode Cloud, Bitrise | **Deferred** | Define before beta; noted as risk |
| Conditional Permit Validity | Implement vs. display-only | **Display-only for V1** | Flag conditions, don't enforce logic |
| Backend Technology | Node.js, Go, Python/FastAPI | **Deferred** | See Backend.md for considerations |
| Database | PostgreSQL + PostGIS, MongoDB | **Deferred** | PostGIS recommended for geo queries |
| Caching (with backend) | Redis, in-memory | **Deferred** | Define with backend architecture |

### Known Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Zone boundary accuracy | Medium | Log edge cases, gather user feedback, iterate |
| Google Maps SDK cost | Low (V1 free tier) | Monitor usage; MapLibre abstraction ready |
| CI/CD not defined | Medium | Define before TestFlight beta |
| Mock data staleness | Low | Version displayed; quarterly review plan |
| Conditional rules complexity | Medium | V1 displays only; implement after validation |

---

## Appendix: Project Structure

```
SFParkingZoneFinder/
├── SFParkingZoneFinder.xcodeproj
├── SFParkingZoneFinder/
│   ├── App/
│   │   ├── SFParkingZoneFinderApp.swift
│   │   ├── AppDelegate.swift
│   │   └── DependencyContainer.swift
│   │
│   ├── Features/
│   │   ├── Main/
│   │   │   ├── Views/
│   │   │   │   ├── MainResultView.swift
│   │   │   │   ├── ZoneStatusCardView.swift
│   │   │   │   ├── RulesSummaryView.swift
│   │   │   │   ├── OverlappingZonesView.swift
│   │   │   │   └── AdditionalInfoView.swift
│   │   │   └── ViewModels/
│   │   │       └── MainResultViewModel.swift
│   │   │
│   │   ├── Map/
│   │   │   ├── Views/
│   │   │   │   ├── FloatingMapWidget.swift
│   │   │   │   ├── MinimizedMapView.swift
│   │   │   │   ├── ExpandedMapView.swift
│   │   │   │   └── GoogleMapsViewRepresentable.swift
│   │   │   ├── ViewModels/
│   │   │   │   └── MapViewModel.swift
│   │   │   └── Adapters/
│   │   │       └── GoogleMapsAdapter.swift
│   │   │
│   │   ├── Onboarding/
│   │   │   ├── Views/
│   │   │   │   ├── WelcomeView.swift
│   │   │   │   ├── LocationPermissionView.swift
│   │   │   │   ├── PermitSetupView.swift
│   │   │   │   └── TutorialOverlayView.swift
│   │   │   └── ViewModels/
│   │   │       └── OnboardingViewModel.swift
│   │   │
│   │   └── Settings/
│   │       ├── Views/
│   │       │   ├── SettingsView.swift
│   │       │   ├── PermitManagementView.swift
│   │       │   └── AboutView.swift
│   │       └── ViewModels/
│   │           └── SettingsViewModel.swift
│   │
│   ├── Core/
│   │   ├── Services/
│   │   │   ├── ZoneService.swift
│   │   │   ├── LocationService.swift
│   │   │   ├── ReverseGeocodingService.swift
│   │   │   ├── PermitService.swift
│   │   │   ├── ZoneLookupEngine.swift
│   │   │   └── RuleInterpreter.swift
│   │   │
│   │   ├── Models/
│   │   │   ├── ParkingZone.swift
│   │   │   ├── ParkingRule.swift
│   │   │   ├── ParkingPermit.swift
│   │   │   ├── ZoneLookupResult.swift
│   │   │   ├── RuleInterpretationResult.swift
│   │   │   └── CityIdentifier.swift
│   │   │
│   │   ├── Protocols/
│   │   │   ├── ZoneDataSourceProtocol.swift
│   │   │   ├── ZoneServiceProtocol.swift
│   │   │   ├── LocationServiceProtocol.swift
│   │   │   ├── MapProviderProtocol.swift
│   │   │   └── ReverseGeocodingServiceProtocol.swift
│   │   │
│   │   └── Extensions/
│   │       ├── CLLocationCoordinate2D+Extensions.swift
│   │       ├── Color+Theme.swift
│   │       └── Date+Formatting.swift
│   │
│   ├── Data/
│   │   ├── Local/
│   │   │   ├── LocalZoneDataSource.swift
│   │   │   └── GeoJSONParser.swift
│   │   │
│   │   ├── Cache/
│   │   │   └── ZoneCache.swift
│   │   │
│   │   └── Repositories/
│   │       ├── ZoneRepository.swift
│   │       └── PermitRepository.swift
│   │
│   └── Resources/
│       ├── sf_parking_zones.json
│       ├── Assets.xcassets/
│       ├── Localizable.strings
│       └── Info.plist
│
├── SFParkingZoneFinderTests/
│   ├── Services/
│   │   ├── ZoneLookupEngineTests.swift
│   │   ├── RuleInterpreterTests.swift
│   │   └── PermitServiceTests.swift
│   │
│   ├── ViewModels/
│   │   ├── MainResultViewModelTests.swift
│   │   └── OnboardingViewModelTests.swift
│   │
│   └── Mocks/
│       ├── MockLocationService.swift
│       ├── MockZoneDataSource.swift
│       └── MockMapProvider.swift
│
└── SFParkingZoneFinderUITests/
    └── (Placeholder for UI tests)
```

---

**Document Owner:** Engineering Team
**Next Review:** Pre-MVP Launch
**Related Documents:** ProductBrief.md, Backend.md, TestPlan.md
