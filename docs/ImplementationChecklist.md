# SF Parking Zone Finder - Implementation Checklist

**Purpose:** Actionable task list for prompting Claude Code to build the app
**Usage:** Copy each task as a prompt, check off when complete

---

## Progress Summary

### 🎯 Minimum Viable Alpha Path

For a functional Alpha release with real data, complete these in order:
1. ✅ S1-S9: iOS app core features (DONE)
2. ✅ S10: Data Pipeline (DONE)
3. ✅ S12: iOS Data Integration - Real pipeline data bundled and tested
4. ✅ S13: Backend Testing - CI/CD and test coverage
5. 🔲 **S14α: TestFlight Alpha Launch** - Deploy to internal testers

**Deferred to Beta:**
- S11: Backend API & Pipeline Automation - Full backend with live data

---

### 🚀 Epic: Alpha Release

| Story | Status | Tasks |
|-------|--------|-------|
| S1: Project Foundation | **COMPLETE** | 12/12 |
| S2: Data Layer | **COMPLETE** | 8/8 |
| S3: Location Services | **COMPLETE** | 6/6 |
| S4: Zone Lookup Engine | **COMPLETE** | 8/8 |
| S5: Rule Interpretation | **COMPLETE** | 6/6 |
| S6: Main Result View | **COMPLETE** | 14/14 |
| S7: Floating Map | **COMPLETE** | 10/10 |
| S8: Onboarding Flow | **COMPLETE** | 10/10 |
| S9: Settings Screen | **COMPLETE** | 8/8 |
| S10: Data Pipeline | **COMPLETE** | 6/6 |
| S12: iOS Data Integration | **COMPLETE** | 9/9 |
| S13: Backend Testing | **COMPLETE** | 4/4 |

| S14α: TestFlight Alpha Launch | In Progress | 2/6 |

**Alpha Progress:** 101/105 tasks complete (96%)

*Note: API testing tasks moved to S13b in Beta (blocked by S11)*

### 🎯 Epic: Beta Release

| Story | Status | Tasks |
|-------|--------|-------|
| S11: Backend API & Pipeline | Not Started | 0/17 |
| S13b: Backend API Testing | Not Started | 0/3 |
| S14: Error Handling | **COMPLETE** | 6/6 |
| S15: UI Polish & Animations | **COMPLETE** | 7/8 |
| S16: CarPlay Support | **COMPLETE** | 8/10 |
| S17: Map Zone Boundaries & Blockface Viz | In Progress | 21/38 |
| S18: Beta Release Prep | Not Started | 0/6 |
| S19: UI Testing | Not Started | 0/8 |
| S20: Performance Optimization | In Progress | 5/14 |
| S21: Zone Card UI Refinements | In Progress | 25/28 |
| S22: CarPlay Experience Update | Not Started | 0/10 |
| S23: Parking Rules & Location Lookups | Not Started | 0/13 |
| S24: Street Cleaning Data | Not Started | 0/13 |
| S25: Metered Parking Layer | Not Started | 0/19 |
| S26: Blockface Migration | Not Started | 0/24 |

**Beta Progress:** 66/219 tasks complete (30%)

---

**Overall Progress:** 167/324 tasks complete (52%)

*Note: Future Enhancement tasks (F-series) not included in progress counts*

---

## Story 1 (S1): Project Foundation

**Goal:** Xcode project set up with dependencies and base architecture

### Tasks

- [x] **1.1** Create a new Xcode project for SF Parking Zone Finder using SwiftUI App template, targeting iOS 16+, with the folder structure defined in TechnicalArchitecture.md

- [x] **1.2** Add Google Maps SDK for iOS as a Swift Package dependency and configure the API key in AppDelegate

- [x] **1.3** Create the DependencyContainer class with protocol-based service registration for dependency injection

- [x] **1.4** Define all service protocols: ZoneServiceProtocol, ZoneDataSourceProtocol, LocationServiceProtocol, MapProviderProtocol, ReverseGeocodingServiceProtocol, RulInterpreterProtocol, ZoneLookupEngineProtocol

- [x] **1.5** Create the core data models: CityIdentifier, ParkingZone, ParkingRule, Coordinate, ZoneType, ZoneMetadata, DataAccuracy

- [x] **1.6** Create the permit data models: ParkingPermit, PermitType

- [x] **1.7** Create the result models: ZoneLookupResult, LookupConfidence, RuleInterpretationResult, PermitValidityStatus, ConditionalFlag

- [x] **1.8** Create the Address model for reverse geocoding results

- [x] **1.9** Set up the app entry point (SFParkingZoneFinderApp.swift) with dependency container initialization

- [x] **1.10** Create Color+Theme extension with app color definitions for validity statuses (valid green, invalid red, conditional yellow, etc.)

- [x] **1.11** Add .gitignore entries for Xcode, Swift, and sensitive files (API keys)

- [x] **1.12** Create a basic README.md with project setup instructions

**Story Complete When:**
- [x] Project builds without errors
- [x] Google Maps SDK initializes (map view renders)
- [x] All protocols and models compile

---

## Story 2 (S2): Data Layer

**Goal:** Mock parking zone data loads and parses correctly

### Tasks

- [ ] **2.1** Create the mock data file sf_parking_zones.json with the schema defined in TechnicalArchitecture.md, including 10-15 sample SF parking zones covering Areas Q, R, A, and some metered zones

- [ ] **2.2** Implement GeoJSONParser to parse sf_parking_zones.json into ParkingZone model arrays

- [x] **2.3** Implement LocalZoneDataSource conforming to ZoneDataSourceProtocol that loads zones from the bundled JSON file

- [x] **2.4** Implement ZoneCache with in-memory storage for loaded zones

- [x] **2.5** Implement ZoneRepository that coordinates between ZoneCache and LocalZoneDataSource

- [ ] **2.6** Register data layer services in DependencyContainer

- [ ] **2.7** Write unit tests for GeoJSONParser covering valid JSON, invalid JSON, and missing fields

- [ ] **2.8** Write unit tests for LocalZoneDataSource verifying zones load correctly

**Story Complete When:**
- [ ] sf_parking_zones.json contains valid sample data for SF
- [ ] Calling ZoneRepository.getZones() returns parsed ParkingZone array
- [ ] Unit tests pass

---

## Story 3 (S3): Location Services

**Goal:** App can acquire device location and reverse geocode to address

### Tasks

- [ ] **3.1** Implement LocationService wrapping CLLocationManager with authorization handling, conforming to LocationServiceProtocol

- [ ] **3.2** Add requestSingleLocation() async method that returns CLLocation or throws error with timeout handling

- [ ] **3.3** Add location accuracy indicator logic to LocationService

- [ ] **3.4** Implement ReverseGeocodingService using CLGeocoder with address caching

- [ ] **3.5** Register location services in DependencyContainer

- [ ] **3.6** Write unit tests for LocationService using mock CLLocationManager

**Story Complete When:**
- [ ] App requests location permission correctly
- [ ] LocationService returns device coordinates
- [ ] ReverseGeocodingService returns formatted address
- [ ] Unit tests pass

---

## Story 4 (S4): Zone Lookup Engine

**Goal:** Given coordinates, determine which parking zone(s) contain that point

### Tasks

- [ ] **4.1** Implement point-in-polygon algorithm as a utility function using ray casting

- [ ] **4.2** Create SpatialIndex class for efficient polygon queries (simplified R-tree or bounding box pre-filter)

- [ ] **4.3** Implement ZoneLookupEngine conforming to ZoneLookupEngineProtocol with findZone(at:) method

- [ ] **4.4** Add boundary detection logic that identifies when user is within 10 meters of a zone edge

- [ ] **4.5** Implement overlapping zone handling that returns all zones containing the point

- [ ] **4.6** Add restrictiveness-based sorting so most restrictive zone is primary when multiple match

- [ ] **4.7** Add LookupConfidence scoring based on GPS accuracy and boundary proximity

- [ ] **4.8** Write comprehensive unit tests for ZoneLookupEngine covering: point inside zone, point outside all zones, point on boundary, overlapping zones

**Story Complete When:**
- [ ] findZone(at:) returns correct zone for test coordinates
- [ ] Boundary cases default to most restrictive zone
- [ ] Overlapping zones all returned in result
- [ ] Unit tests pass with >90% coverage

---

## Story 5 (S5): Rule Interpretation Engine

**Goal:** Determine permit validity and generate human-readable rule summaries

### Tasks

- [ ] **5.1** Implement RuleInterpreter conforming to RuleInterpreterProtocol with interpretRules(for:userPermits:at:) method

- [ ] **5.2** Implement permit matching logic that compares user permits against zone's validPermitAreas

- [ ] **5.3** Implement PermitValidityStatus determination (valid, invalid, conditional, noPermitRequired, multipleApply)

- [ ] **5.4** Implement generateRuleSummary() that creates human-readable bullet points from ParkingRule array

- [ ] **5.5** Add conditional flag identification that marks time-based restrictions as display-only

- [ ] **5.6** Write unit tests for RuleInterpreter covering all validity statuses and edge cases

**Story Complete When:**
- [ ] interpretRules() returns correct validity for all permit scenarios
- [ ] Rule summaries are readable and accurate
- [ ] Conditional rules flagged but not enforced
- [ ] Unit tests pass with >90% coverage

---

## Story 6 (S6): Main Result View (Primary UI)

**Goal:** Full-screen text result view displaying zone, validity, and rules

### Tasks

- [ ] **6.1** Create MainResultViewModel that coordinates location, zone lookup, and rule interpretation

- [ ] **6.2** Create ZoneStatusCardView showing zone name in large bold text

- [ ] **6.3** Create ValidityBadgeView with color-coded status, shape indicators for accessibility, and status text

- [ ] **6.4** Create RulesSummaryView displaying rules as bullet points with expandable "View Full Rules" section

- [ ] **6.5** Create OverlappingZonesView that displays all applicable zones when multiple match, showing validity for each

- [ ] **6.6** Create AdditionalInfoView with last updated timestamp, current address, refresh button, and report issue link

- [ ] **6.7** Create ConditionalFlagsView to display flagged conditional rules (time restrictions, etc.)

- [ ] **6.8** Assemble MainResultView combining all components in a ScrollView

- [ ] **6.9** Add pull-to-refresh functionality that triggers location refresh

- [ ] **6.10** Add loading state view shown during location acquisition and zone lookup

- [ ] **6.11** Implement Dynamic Type support for all text elements

- [ ] **6.12** Add VoiceOver accessibility labels and hints to all interactive elements

- [ ] **6.13** Write unit tests for MainResultViewModel

- [ ] **6.14** Create a temporary debug entry point to test MainResultView with mock data

**Story Complete When:**
- [ ] Main screen shows zone name, validity badge, and rules
- [ ] Overlapping zones display correctly
- [ ] Pull to refresh works
- [ ] VoiceOver reads all content correctly
- [ ] Dynamic Type scales properly

---

## Story 7 (S7): Floating Map Component

**Goal:** Minimized floating map with expansion to full-screen

### Tasks

- [ ] **7.1** Create GoogleMapsAdapter conforming to MapProviderProtocol that wraps GMSMapView

- [ ] **7.2** Create GoogleMapsViewRepresentable (UIViewRepresentable) for SwiftUI integration

- [ ] **7.3** Create MapViewModel managing map state, user location, visible zones, and selected zone

- [ ] **7.4** Create MinimizedMapView (120x120pt) showing user location dot and current zone boundary

- [ ] **7.5** Style MinimizedMapView with rounded corners, shadow, and semi-transparent overlay

- [ ] **7.6** Create ExpandedMapView (full-screen) with all nearby zones color-coded

- [ ] **7.7** Add "Back to Results" button to ExpandedMapView that's always visible

- [ ] **7.8** Add zone tap handling in ExpandedMapView that shows ZoneInfoCard with zone details

- [ ] **7.9** Create FloatingMapWidget that positions MinimizedMapView as overlay on MainResultView

- [ ] **7.10** Add tap gesture to FloatingMapWidget that presents ExpandedMapView as sheet

**Story Complete When:**
- [ ] Floating map renders at correct size and position
- [ ] User location dot visible on map
- [ ] Current zone boundary drawn on map
- [ ] Tap expands to full-screen map
- [ ] Full-screen map shows all nearby zones
- [ ] Back button returns to result view

---

## Story 8 (S8): Onboarding Flow

**Goal:** First-launch experience with permissions and permit setup

### Tasks

- [ ] **8.1** Create OnboardingViewModel managing onboarding state and permit collection

- [ ] **8.2** Create WelcomeView with app branding, tagline, illustration, and "Get Started" button

- [ ] **8.3** Create LocationPermissionView explaining why location is needed with privacy note

- [ ] **8.4** Implement location permission request handling with graceful denial flow

- [ ] **8.5** Create PermitTypePicker showing permit type options (RPP active, others disabled/coming soon)

- [ ] **8.6** Create PermitAreaGrid for multi-select of RPP areas (A-Z, Q, R, S, T, U, V, W, X, Y)

- [ ] **8.7** Create PermitSetupView combining type picker and area grid with "Continue" and "Skip" options

- [ ] **8.8** Implement permit saving to UserDefaults via PermitService

- [ ] **8.9** Create TutorialOverlayView (optional, dismissible) showing how to use main screen and map

- [ ] **8.10** Create OnboardingContainerView that manages navigation through all onboarding steps and transitions to MainResultView

**Story Complete When:**
- [x] New user sees welcome screen on first launch
- [x] Location permission requested with explanation
- [x] User can select multiple permit areas
- [x] Permits saved and persist across launches
- [x] Onboarding completes and shows main view
- [x] Returning users skip directly to main view

---

## Story 9 (S9): Settings Screen

**Goal:** User can manage permits and preferences

### Tasks

- [x] **9.1** Create SettingsViewModel managing user preferences and permit data

- [x] **9.2** Create PermitManagementView listing current permits with add/edit/delete functionality

- [x] **9.3** Create AddPermitView for adding new permits (reuse PermitAreaGrid)

- [x] **9.4** Add map preferences section: toggle floating map visibility, map position picker

- [x] **9.5** Create AboutView showing app version, data version, privacy policy, and open source licenses

- [x] **9.6** Add Help section with FAQ placeholder, report issue email link, and rate app link

- [x] **9.7** Assemble SettingsView with all sections using List and NavigationLink

- [x] **9.8** Add settings gear icon to MainResultView bottom section linking to SettingsView

**Story Complete When:**
- [x] Settings accessible from main view
- [x] User can add, edit, delete permits
- [x] Map preferences persist and apply
- [x] About information displays correctly

---

# Alpha Release: Backend Integration

## Story 10 (S10): Data Pipeline

**Goal:** ETL pipeline to fetch and transform official SF parking data from DataSF and SFMTA

### Data Sources

| Source | Dataset | Key Data |
|--------|---------|----------|
| **DataSF** | Map of Parking Regulations (Blockface) | RPP flags, area codes, time limits, special restrictions, geometry |
| **DataSF** | Parking Meters Dataset | Meter locations, cap color/type |
| **SFMTA** | RPP Area Polygons (ArcGIS) | Official zone boundaries |

### Tasks

- [x] **14.1** Create DataSF Blockface data fetcher (parking regulations, blockface geometry)

- [x] **14.2** Create DataSF Meters data fetcher (meter locations, types)

- [x] **14.3** Create SFMTA ArcGIS RPP polygon fetcher (zone boundaries)

- [x] **14.4** Implement data transformer (normalize schema, merge overlapping sources)

- [x] **14.5** Implement data validator (geometry validation, required fields check)

- [x] **14.6** Set up scheduled pipeline (daily for DataSF, weekly for SFMTA)

**Story Complete When:**
- [x] Pipeline successfully fetches data from all sources
- [x] Data transforms into normalized schema
- [x] Validator catches invalid/missing data
- [x] Pipeline runs on schedule without errors

---

## Story 11 (S11): Backend API & Pipeline Automation

**Goal:** REST API service to serve zone data + automated pipeline for data freshness

### Tasks

#### Database & API
- [ ] **11.1** Set up PostgreSQL + PostGIS database with spatial indexes

- [ ] **11.2** Implement database schema (cities, zones, rules, data_versions tables)

- [ ] **11.3** Create FastAPI service with zone lookup endpoint (POST /lookup)

- [ ] **11.4** Implement spatial queries using PostGIS (point-in-polygon)

- [ ] **11.5** Add Redis caching layer for zone data and lookup results

- [ ] **11.6** Implement API rate limiting and API key authentication

#### Pipeline Automation
- [ ] **11.7** Set up scheduled pipeline execution (GitHub Actions or cron)

- [ ] **11.8** Configure pipeline to write output to database instead of JSON file

- [ ] **11.9** Add pipeline health monitoring and alerting

- [ ] **11.10** Implement data versioning with rollback capability

#### Deployment
- [ ] **11.11** Deploy API to cloud infrastructure (AWS/GCP with auto-scaling)

- [ ] **11.12** Set up staging environment for testing

- [ ] **11.13** Configure CI/CD for automatic API deployment

#### iOS Integration
- [ ] **11.14** Create RemoteZoneDataSource conforming to ZoneDataSourceProtocol

- [ ] **11.15** Add API client with async/await and error handling

- [ ] **11.16** Implement offline fallback (cache last successful response)

- [ ] **11.17** Add feature flag to switch between bundled and remote data

**Story Complete When:**
- [ ] API returns correct zones for test coordinates
- [ ] Response time < 200ms (p95)
- [ ] Pipeline runs automatically on schedule
- [ ] iOS app can use remote data with offline fallback
- [ ] Deployed and accessible from iOS app

---

## Story 12 (S12): iOS Data Integration (Static Bundle)

**Goal:** iOS app uses real parking data from pipeline output (bundled at build time)

### Tasks

- [x] **12.1** Create conversion script: pipeline output → iOS-compatible GeoJSON schema

- [x] **12.2** Update LocalZoneDataSource to load official parking_zones.json instead of mock data

- [x] **12.3** Run pipeline on machine with network access, generate parking_data.json

- [x] **12.4** Bundle pipeline output JSON into iOS app Resources folder

- [x] **12.5** Display data version and "last updated" in Settings/About

- [x] **12.6** Add data source attribution (DataSF, SFMTA) in About screen

- [x] **12.7** Create update script to refresh bundled data from pipeline output

- [x] **12.8** Test iOS app loads and displays real zone data correctly

- [x] **12.9** Verify point-in-polygon lookup works with official zone boundaries

**Story 12 Complete When:**
- [x] iOS app displays real SF parking zone data
- [x] Zone lookup returns accurate results for test locations
- [x] Data source/version visible in Settings
- [x] Process documented for updating bundled data

---

## Story 13 (S13): Backend Testing (Alpha Scope)

**Goal:** Test coverage for data pipeline (API tests moved to Beta with S11)

### Tasks

- [x] **13.1** Write unit tests for Data Pipeline ETL components

- [x] **13.2** Write integration tests for DataSF and SFMTA API fetchers

- [x] **13.3** Set up CI/CD pipeline with automated test runs

- [x] **13.4** Add test coverage reporting

**Story 13 Complete When:**
- [x] Pipeline unit tests pass
- [x] Pipeline integration tests pass
- [x] CI/CD runs tests automatically on push

---

## Story 14α (S14α): TestFlight Alpha Launch

**Goal:** Deploy bundled-data Alpha to TestFlight for internal testing

### Tasks

- [ ] **14α.1** Configure App Store Connect: create app record, set bundle ID, app name, and primary category

- [ ] **14α.2** Add app icons for all required sizes (1024x1024 App Store, plus device sizes)

- [x] **14α.3** Create launch screen with app branding (storyboard or SwiftUI)

- [x] **14α.4** Write privacy policy covering location data usage and add to Settings/About

- [ ] **14α.5** Archive build, resolve any signing/capability issues, and upload to TestFlight

- [ ] **14α.6** Set up internal testing group and distribute to team (3-5 internal testers)

**Story 14α Complete When:**
- [ ] App available on TestFlight (internal testing)
- [ ] App installs and launches without crash
- [ ] Core flow works: onboarding → permit setup → zone lookup
- [ ] Privacy policy accessible in app

---

## Story 13b (S13b): Backend API Testing (Beta - requires S11)

**Goal:** Test coverage for Backend API (blocked until S11 complete)

### Tasks

- [ ] **13b.1** Write unit tests for Backend API endpoints

- [ ] **13b.2** Write integration tests for PostGIS spatial queries

- [ ] **13b.3** Write end-to-end tests for iOS ↔ Backend communication

**Story 13b Complete When:**
- [ ] All backend API unit tests pass
- [ ] E2E tests confirm iOS app works with live backend

---

# Beta Release

## Story 14 (S14): Error Handling

**Goal:** Graceful error states with clear user guidance

### Tasks

- [x] **14.1** Create LocationDeniedView with explanation and button to open Settings app

- [x] **14.2** Create LocationUnavailableView for GPS timeout scenarios with retry button

- [x] **14.3** Create OutsideCoverageView shown when user is outside SF

- [x] **14.4** Create UnknownAreaView for locations in SF without zone data (distinct from outside coverage)

- [x] **14.5** Create DataLoadingErrorView for data parsing failures

- [x] **14.6** Integrate error views into MainResultView based on state

**Story 14 Complete When:**
- [x] All error scenarios show appropriate message
- [x] Error views have actionable next steps
- [x] Users can recover from errors easily

---

## Story 15 (S15): UI Polish & Animations

**Goal:** Enhanced visual polish and delightful user experience

### Tasks

- [x] **15.1** Update deprecated Map initializers to iOS 17+ MapContentBuilder syntax

- [x] **15.2** Add AccentColor to Assets.xcassets with appropriate light/dark variants

- [ ] **15.3** Improve floating map positioning and responsiveness (deferred)

- [x] **15.4** Add smooth animations for state transitions (loading, error, success)

- [x] **15.5** Implement skeleton loading states for zone information

- [x] **15.6** Polish typography hierarchy and spacing consistency

- [x] **15.7** Add subtle haptic feedback for user interactions

- [x] **15.8** Implement Reduce Motion support checking accessibilityReduceMotion

**Story 15 Complete When:**
- [x] No deprecation warnings in codebase
- [x] Consistent visual polish throughout app
- [x] Smooth, delightful animations
- [x] Full accessibility support

---

## Story 16 (S16): CarPlay Support

**Goal:** Allow drivers to check parking zone status via CarPlay dashboard

### Tasks

- [x] **16.1** Add CarPlay entitlement and configure Info.plist

- [x] **16.2** Create CarPlaySceneDelegate to handle CarPlay connection

- [x] **16.3** Implement CPTemplate-based UI showing current zone and validity

- [x] **16.4** Create CPInformationTemplate for zone display (CPPointOfInterestTemplate not needed)

- [x] **16.5** Zone display uses CPInformationTemplate (CPMapTemplate deferred to S17)

- [x] **16.6** Implement automatic zone updates while driving

- [x] **16.7** Add voice feedback option for zone changes (using AVSpeechSynthesizer)

- [x] **16.8** Handle CarPlay connect/disconnect lifecycle

- [ ] **16.9** Test on CarPlay Simulator and physical CarPlay unit

- [ ] **16.10** Add CarPlay support documentation

**Story 16 Complete When:**
- [x] App appears in CarPlay dashboard
- [x] Zone status visible while driving
- [x] Updates automatically as location changes
- [x] Voice feedback announces zone changes

---

## Story 17 (S17): Map Zone Boundaries & Blockface Visualization

**Goal:** Display parking zone boundaries and blockface parking lanes as visual polygons on the expanded map view

### Technical Notes

> **MapContentBuilder Limitations (discovered in Alpha):** SwiftUI's `@MapContentBuilder` has limited support for control flow (no `if let`, complex `ForEach` with conditionals). Initial attempts to render zone polygons using `MapPolygon` and `MapPolyline` with `foregroundStyle()` failed due to these limitations. Consider using `MKMapView` with `UIViewRepresentable` and `MKPolygonRenderer` for reliable polygon rendering, or explore MapKit overlay approach outside of `@MapContentBuilder`.

> **Async Zone Loading Bug (discovered Nov 2025):** Zone overlays were only loaded in `makeUIView`. If zones arrived after map creation (async loading), overlays never appeared. Fixed by adding `overlaysLoaded` flag and `loadOverlays()` helper in `updateUIView` to load overlays when zones become available.

> **Blockface Offset Strategy (Nov 2025):** Blockfaces represent parking lanes on one side of a street. To visualize them, centerlines must be offset perpendicular to create lane polygons. The challenge: determining which direction to offset based on side labels (NORTH/SOUTH/EAST/WEST/EVEN/ODD) and street bearing. Solution: bearing-aware algorithm that maps side labels to desired compass directions, calculates both perpendiculars, and selects the one that aligns best with the desired direction. This handles all street orientations correctly.

### Tasks

#### Zone Boundary Display
- [ ] **17.1** Create ZoneOverlay model with polygon coordinates compatible with both MapKit and Google Maps

- [x] **17.2** Implement zone polygon overlays for each parking zone from mock data boundaries

- [x] **17.3** Add overlay renderer to style zone polygons with semi-transparent fill and border

- [x] **17.4** Style current zone with accent color fill (20% opacity) and thick border

- [x] **17.5** Style adjacent/nearby zones with lighter differentiated colors

- [x] **17.6** Calculate zone polygon centroids and add zone label annotations (large, bold letters)

- [x] **17.7** Implement tap gesture on zone overlays to show ZoneInfoCard popup

- [x] **17.8** Create ZoneInfoCard popup view with zone name, type, basic rules, and "View Details" button

#### Zone Color System
- [x] **17.9** Define distinct color palette for all RPP zones (A-Z, AA-LL) with good visual differentiation

- [x] **17.10** Create ZoneColorProvider service that maps zone codes to SwiftUI/UIKit colors

- [ ] **17.11** Store zone colors in data model or configuration (support both light/dark mode variants)

- [x] **17.12** Implement color-coded polygon overlays on expanded map view (full screen only)

- [ ] **17.13** Add legend or key showing zone colors (optional, toggleable)

#### Zone Overlay Fixes
- [x] **17.20** Fix zone overlays not loading when zones arrive after map creation (async loading bug)

- [x] **17.21** Add `overlaysLoaded` flag to coordinator to track overlay loading state

- [x] **17.22** Create `loadOverlays()` helper function for deferred overlay loading from `updateUIView`

- [x] **17.23** Reduce stroke prominence (3.0/1.5 → 2.0/1.0 line width)

- [x] **17.24** Improve multi-permit zone dash pattern ([8,4] → [4,2], same width as regular)

#### Boundary Geometry Cleanup
- [ ] **17.25** Make zone boundaries more geometric (simplify irregular edges, straighten block-aligned segments)

- [ ] **17.26** Clean up boundary intersections at corners (resolve overlapping/jagged edges where zones meet)

#### Blockface Visualization (PoC - Nov 2025)
- [x] **17.27** Load blockface data from GeoJSON with centerline coordinates and parking regulations
- [x] **17.28** Implement basic perpendicular offset to create parking lane polygons from centerlines
- [x] **17.29** Add 4-category color coding for blockfaces (free, permit valid, permit invalid, paid)
- [x] **17.30** Implement bearing-aware offset direction selection (fixes incorrect offsets for different street orientations)
- [x] **17.31** Create blockface offset strategy design document
- [x] **17.32** Add developer settings for blockface width, offset adjustments, and visualization toggles
- [ ] **17.33** Evaluate blockface rendering performance with full dataset (18K+ blockfaces)
- [ ] **17.34** Implement blockface simplification/clustering for better performance at city-wide zoom levels
- [ ] **17.35** Improve bearing-aware offset algorithm to handle curved streets and complex geometries:
  - Add local bearing calculation per vertex (not just overall bearing)
  - Smooth offsets at sharp turns to avoid polygon self-intersection
  - Handle multi-segment blockfaces with varying bearings
  - Test with diagonal streets (Market St, Geary Blvd) and curved roads (Twin Peaks)

#### Blockface Data Integration (Pipeline - Nov 2025)
- [ ] **17.36** Implement spatial join between blockface geometries and parking regulations CSV:
  - Load regulations CSV with geometry from "shape" column (7,784 records)
  - Spatially match regulations to blockface centerlines (buffer, intersects, or nearest)
  - Handle one-to-many matches (multiple regulations per blockface)
  - Populate `regulations: []` field in blockface JSON with matched data
- [ ] **17.37** Extract regulation fields from matched CSV records:
  - Map REGULATION, DAYS, HOURS, HRS_BEGIN, HRS_END to app schema
  - Extract RPP areas (RPPAREA1/2/3) and time limits (HRLIMIT)
  - Parse EXCEPTIONS field for special conditions
  - Convert FROM_TIME/TO_TIME to enforcement hours
- [ ] **17.38** Validate spatial join quality:
  - Check match rate (% of blockfaces with regulations)
  - Identify blockfaces with multiple conflicting regulations
  - Test sample blockfaces against ground truth (street signs)
  - Handle edge cases (no match, ambiguous match)
- [ ] **17.39** Update conversion script to output blockfaces with regulations:
  - Modify convert_geojson_to_app_format.py to include spatial join
  - Add regulation validation (required fields, data types)
  - Export enhanced blockface JSON with regulations populated
  - Document regulation schema in app data model

#### Map Provider Abstraction
- [ ] **17.14** Create MapProviderProtocol abstraction layer for switching between map providers

- [ ] **17.15** Implement AppleMapKitAdapter conforming to MapProviderProtocol (current default)

- [ ] **17.16** Implement GoogleMapsAdapter conforming to MapProviderProtocol (requires Google Maps SDK)

- [ ] **17.17** Implement MapLibreAdapter conforming to MapProviderProtocol (open source alternative using OpenStreetMap tiles)

- [ ] **17.18** Add map provider selection to Settings (Apple Maps, Google Maps, MapLibre/OSM)

- [ ] **17.19** Persist map provider preference and apply on app launch

**Story 17 Complete When:**
- [ ] Expanded map shows all zone boundaries as colored polygons
- [ ] Current zone highlighted distinctly from other zones
- [ ] Zone letters visible on map at various zoom levels
- [ ] Tapping a zone shows info card with zone details
- [ ] User can switch between Apple Maps, Google Maps, and MapLibre in Settings
- [ ] Zone boundaries render correctly on all supported map providers
- [x] Blockface PoC demonstrates parking lane visualization with correct offset directions
- [ ] Blockface layer performs well with full dataset (18K+ blockfaces)

---

## Story 23 (S23): Parking Rules & Location-Based Lookups

**Goal:** Evaluate and implement methods for calculating parking rules and "Park Until" times based on map taps and current location, enabling blockface-based data layer

### Context

Currently, the app uses RPP zone polygons for lookups. To transition to blockface-based data, we need to determine parking rules and time limits for any tapped location or current GPS position. This is more complex than polygon lookup because:
- Blockfaces are linear features (street segments), not area polygons
- Users can tap/be located on the street itself or near it (sidewalk, building)
- Multiple blockfaces may be nearby (both sides of street, intersections)
- Rules may differ by side of street, time of day, and street cleaning schedules

**Blocks:** Replacing current zone overlay layer with blockface data layer

### Tasks

#### Spatial Lookup Methods
- [ ] **23.1** Research and document spatial lookup approaches:
  - Nearest blockface by distance (buffer zone around tap point)
  - Snap-to-street algorithm (project point to nearest street segment)
  - Directional awareness (detect which side of street user is on)
  - Intersection handling (multiple blockfaces within threshold)

- [ ] **23.2** Prototype distance-based lookup (find all blockfaces within N meters of tap point)

- [ ] **23.3** Evaluate snapping accuracy with different buffer distances (5m, 10m, 15m)

- [ ] **23.4** Test lookup performance with full blockface dataset (18K+ segments)

#### Rule Aggregation & Conflicts
- [ ] **23.5** Design algorithm for handling multiple blockfaces at one location:
  - Show all nearby blockfaces with distance indicators
  - Rank by most restrictive / closest / most relevant
  - Display conflicting rules clearly (different sides of street)

- [ ] **23.6** Implement "Park Until" calculation from blockface time limits and enforcement hours

- [ ] **23.7** Handle edge cases:
  - Tap point equidistant from multiple streets (intersection)
  - Blockface with no parking vs. permit parking vs. metered
  - Conflicting data (RPP area + street cleaning + time limit)

#### User Experience Design
- [ ] **23.8** Design UI for tap-based blockface lookup results:
  - Show primary blockface (closest/most relevant)
  - Indicate "other side of street" if different rules
  - Display nearby alternative parking if current spot is invalid

- [ ] **23.9** Design current location indicator:
  - GPS accuracy circle overlay
  - "You are here" on specific blockface
  - Confidence indicator for lookup (high/medium/low based on GPS accuracy)

- [ ] **23.10** Create comparison document: zone-based vs blockface-based lookup tradeoffs

#### Testing & Validation
- [ ] **23.11** Test with real-world scenarios (Mission District, SOMA, Presidio)

- [ ] **23.12** Validate against known ground truth (physical street signs)

- [ ] **23.13** A/B test with users: zone polygons vs blockface lookups

**Story 23 Complete When:**
- [ ] Spatial lookup method selected and documented with tradeoffs
- [ ] Prototype demonstrates accurate blockface selection for taps and GPS location
- [ ] "Park Until" calculation works correctly with blockface time limits
- [ ] UI design approved for blockface-based lookup results
- [ ] Performance acceptable for real-time lookups (< 100ms)
- [ ] Decision made: proceed with blockface layer or hybrid approach

---

## Story 24 (S24): Street Cleaning Data Integration

**Goal:** Add street cleaning schedule data to base dataset and display in UI

### Data Source
- **DataSF:** Street Sweeping Schedule dataset (routes, days, times)

### Tasks

#### Data Pipeline
- [ ] **24.1** Create DataSF street cleaning data fetcher

- [ ] **24.2** Transform street cleaning data to match blockface schema (geometry + schedule)

- [ ] **24.3** Join street cleaning schedules with blockface data (spatial or street name matching)

- [ ] **24.4** Add validation for cleaning schedule fields (days, start time, end time)

- [ ] **24.5** Update data pipeline to include street cleaning in daily runs

#### Data Model
- [ ] **24.6** Extend blockface/zone data model with street cleaning fields:
  - `streetCleaningDays`: Array of weekdays
  - `streetCleaningStartTime`: Time
  - `streetCleaningEndTime`: Time
  - `streetCleaningSide`: "BOTH", "NORTH", "SOUTH", "EAST", "WEST"

- [ ] **24.7** Update GeoJSON parser to handle street cleaning fields

#### UI Display
- [ ] **24.8** Add street cleaning indicator to zone/blockface cards:
  - "🧹 Street Cleaning: Wed 8AM-10AM" badge
  - Warning color if cleaning is today/soon

- [ ] **24.9** Update "Park Until" calculation to consider street cleaning times

- [ ] **24.10** Show "next street cleaning" info in expanded card

- [ ] **24.11** Add street cleaning overlay toggle to map (show all streets with upcoming cleaning)

#### Notifications (Future)
- [ ] **24.12** Design notification logic for pre-cleaning alerts (1 hour before)

- [ ] **24.13** Add "street cleaning today" to daily parking summary notification

**Story 24 Complete When:**
- [ ] Street cleaning data integrated into pipeline and bundled with app
- [ ] Street cleaning schedules display correctly on zone/blockface cards
- [ ] "Park Until" accounts for upcoming street cleaning times
- [ ] Map overlay shows streets with cleaning schedules (optional toggle)
- [ ] Data updates automatically with pipeline runs

---

## Story 25 (S25): Metered Parking Layer

**Goal:** Add metered parking data with cost information and toggleable map layer

### Data Source
- **DataSF:** Parking Meters dataset (locations, rates, time limits, cap color)

### Tasks

#### Data Pipeline
- [ ] **25.1** Create DataSF parking meters data fetcher

- [ ] **25.2** Transform meter data to app schema (location, rate, time limit, payment methods)

- [ ] **25.3** Spatially join meters with blockfaces (associate meters with nearby blockface segments)

- [ ] **25.4** Tag blockfaces with meter data:
  - `hasMeters`: Boolean
  - `meterRate`: String (e.g., "$3.50/hr")
  - `meterTimeLimit`: Minutes
  - `meterOperatingHours`: Time range
  - `meterCapColor`: String (for cap color coding)

- [ ] **25.5** Validate meter data (rate format, operating hours, cap color)

- [ ] **25.6** Update pipeline to include meter data in daily runs

#### Data Model
- [ ] **25.7** Extend blockface data model with meter fields (see 25.4)

- [ ] **25.8** Update GeoJSON parser to handle metered parking fields

- [ ] **25.9** Create `MeterInfo` model with rate, limit, hours, payment methods

#### Map Layer
- [ ] **25.10** Create toggleable "Metered Parking" map layer (on/off in settings or map controls)

- [ ] **25.11** Add meter pin icons at meter locations (color-coded by cap color)

- [ ] **25.12** Color-code metered blockfaces differently from permit zones

- [ ] **25.13** Add meter cluster markers at higher zoom levels (performance optimization)

#### UI Display
- [ ] **25.14** Update zone/blockface cards to show meter information:
  - "💰 Metered: $3.50/hr, 2hr limit"
  - Operating hours (e.g., "Mon-Sat 9AM-6PM")
  - Payment methods (PayByPhone, ParkMobile, coins, card)

- [ ] **25.15** Add "Pay Meter" button with deep links to payment apps

- [ ] **25.16** Show meter cost calculation in "Park Until" section (e.g., "2 hours = $7.00")

- [ ] **25.17** Display meter time limit in "Park Until" calculation

#### Enhanced Lookup Logic
- [ ] **25.18** Update parking rules logic to handle metered blockfaces:
  - If permit valid + metered → show both permit and meter info
  - If no permit + metered → show meter as primary parking option
  - If meter expired/broken → fall back to base blockface rules

- [ ] **25.19** Add "nearest available parking" feature:
  - Find closest non-metered or permit-valid blockface if tapped spot is metered/invalid

**Story 25 Complete When:**
- [ ] Meter data integrated into pipeline and bundled with app
- [ ] Metered parking layer toggleable on map with meter pins
- [ ] Metered blockfaces display rate, time limit, and operating hours
- [ ] "Pay Meter" deep links work for supported payment apps
- [ ] "Park Until" calculation includes meter time limits
- [ ] Lookup logic correctly handles permit + metered combinations
- [ ] Performance acceptable with full meter dataset (28K+ meters)

---

## Story 26 (S26): Blockface Data Layer Migration

**Goal:** Migrate from zone-based to blockface-based parking lookups using a hybrid approach with phased rollout

### Context

**Current:** Zone polygons (24 zones) with zone-wide rules
**Proposed:** Blockface segments (18K+) with street-level granularity
**Approach:** Hybrid system (blockfaces for detail, zones for context/fallback)
**Risk:** Medium (mitigated through phasing, testing, and fallback logic)

> **See:** `docs/BlockfaceMigrationStrategy.md` for comprehensive risk analysis and mitigation strategies

### Tasks

#### Phase 1: Database & Pipeline Infrastructure
- [ ] **26.1** Set up PostgreSQL + PostGIS database for central parking data storage

- [ ] **26.2** Implement database schema with spatial indexes (blockfaces, zones, meters, cleaning)

- [ ] **26.3** Update pipeline to write to database instead of JSON files only

- [ ] **26.4** Add data versioning and rollback capability to database

- [ ] **26.5** Implement GeoJSON export from database for app bundling

- [ ] **26.6** Set up pipeline health monitoring and alerting

#### Phase 2: Feature Flag Architecture
- [ ] **26.7** Implement feature flag system for toggling blockface vs zone lookup

- [ ] **26.8** Add remote config support (can toggle flags without app update)

- [ ] **26.9** Create kill switch for instant rollback to zone lookup

- [ ] **26.10** Implement A/B testing framework for gradual rollout (5% → 25% → 50% → 100%)

#### Phase 3: Hybrid Lookup Logic
- [ ] **26.11** Implement dual lookup mode (run both blockface and zone lookup, compare results)

- [ ] **26.12** Add confidence scoring (high/medium/low based on GPS accuracy and distance)

- [ ] **26.13** Design fallback logic (use zone when blockface lookup uncertain)

- [ ] **26.14** Create "smart default" algorithm (most restrictive when ambiguous)

- [ ] **26.15** Implement logging for lookup discrepancies (blockface vs zone disagreement)

#### Phase 4: Enhanced UI for Blockface Results
- [ ] **26.16** Design result card for blockface-based lookups:
  - Primary blockface (closest/most relevant)
  - "Other side of street" indicator if different rules
  - Confidence indicator (high/medium/low)
  - Map visualization highlighting selected blockface

- [ ] **26.17** Add manual override (user can tap map to select specific blockface)

- [ ] **26.18** Create "Why this blockface?" explanation dialog

- [ ] **26.19** Update onboarding tutorial for blockface-based lookups

#### Phase 5: Testing & Validation
- [ ] **26.20** Validate blockface data against ground truth (random sample of 100 blockfaces vs. street signs)

- [ ] **26.21** A/B test UX with beta users (blockface vs zone, measure satisfaction)

- [ ] **26.22** Performance testing with full dataset (ensure < 100ms lookup time)

- [ ] **26.23** Test rollback procedure (verify can revert to zone lookup within 1 hour)

#### Phase 6: Production Rollout & Monitoring
- [ ] **26.24** Gradual rollout with monitoring:
  - Week 1: 5% of users with blockface lookup enabled
  - Week 2: 25% rollout if metrics healthy (crash rate < 0.1%, accuracy > 90%)
  - Week 3: 50% rollout if no critical issues
  - Week 4: 100% rollout with zone fallback always available

**Story 26 Complete When:**
- [ ] Database and pipeline infrastructure operational
- [ ] Feature flag system with remote toggle and kill switch
- [ ] Hybrid lookup logic implemented with confidence scoring
- [ ] Enhanced UI tested and approved by beta users
- [ ] Ground truth validation shows < 2% error rate
- [ ] A/B test shows > 70% users prefer blockface lookup
- [ ] Performance benchmarks met (< 100ms lookup, < 2s app startup)
- [ ] 100% rollout complete with zone fallback operational
- [ ] Zero critical bugs preventing rollback

**Migration Decision Points:**
1. **After S23:** Proceed with migration if lookup accuracy > 90% and performance < 100ms
2. **After S24-25:** Proceed with beta if data quality acceptable (< 2% errors)
3. **After 5% rollout:** Proceed to 25% if crash rate < 0.1% and no critical bugs
4. **After 50% rollout:** Proceed to 100% if user satisfaction > 80%

**Rollback Triggers:**
- Crash rate > 1% related to blockface lookup
- User-reported accuracy issues > 5%
- Performance degradation > 200ms (p95)
- Critical bug discovered with no immediate fix

---

## Story 18 (S18): Beta Release Prep

**Goal:** App ready for TestFlight distribution

### Tasks

- [ ] **18.1** Configure App Store Connect: create app record, set bundle ID, configure app information

- [ ] **18.2** Add app icons for all required sizes

- [ ] **18.3** Create launch screen / splash screen

- [ ] **18.4** Write privacy policy and add to app / settings

- [ ] **18.5** Archive build and upload to TestFlight

- [ ] **18.6** Distribute to beta testers (target: 50+ SF residents)

**Story 18 Complete When:**
- [ ] App available on TestFlight
- [ ] Beta testers can install and use app
- [ ] No crash on launch for any tester
- [ ] Feedback collection mechanism in place

---

## Story 19 (S19): UI Testing

**Goal:** Comprehensive UI test coverage for finalized user flows

### Tasks

- [ ] **19.1** Set up XCUITest target and configure test schemes

- [ ] **19.2** Create UI test for complete onboarding flow (welcome → permissions → permits → main)

- [ ] **19.3** Create UI test for main result view displaying zone correctly

- [ ] **19.4** Create UI test for map expand and collapse

- [ ] **19.5** Create UI test for settings navigation and permit management

- [ ] **19.6** Create UI test for pull-to-refresh location update

- [ ] **19.7** Create UI test for error state handling (mock location denied)

- [ ] **19.8** Add accessibility identifiers to all interactive elements for reliable testing

**Story 19 Complete When:**
- [ ] UI test target builds and runs
- [ ] All critical user flows have UI tests
- [ ] Tests pass on simulator
- [ ] Tests validate finalized UI polish

---

## Story 20 (S20): Performance Optimization

**Goal:** Optimize zone lookup and data loading for real-world performance with large datasets (83K+ parcels)

### Tasks

#### Spatial Index Optimization
- [x] **20.1** Implement R-tree spatial index for zone boundaries using bounding box pre-filtering

- [x] **20.2** Add zone boundary bounding box caching to avoid recalculating during lookup

- [x] **20.3** Optimize point-in-polygon to early-exit on bounding box miss

#### Data Loading Optimization
- [ ] **20.4** Implement lazy loading for zone boundaries (load metadata first, boundaries on demand)

- [ ] **20.5** Add background data loading with progress indicator on app launch

- [ ] **20.6** Profile and optimize JSON parsing for large zone files (>5MB)

#### Memory Management
- [ ] **20.7** Implement zone boundary simplification for map display (reduce polygon complexity)

- [ ] **20.8** Add memory pressure handling to release cached zones when needed

- [ ] **20.9** Profile memory usage with full SF dataset and optimize if >100MB

#### Lookup Performance
- [x] **20.10** Benchmark zone lookup time with 24 zones × 3,673 boundaries (Zone U scale)

- [ ] **20.11** Target <100ms lookup time for 95th percentile on iPhone 12+

- [x] **20.12** Add performance logging to track lookup times in production builds

#### Startup Performance
- [ ] **20.13** Measure cold start time with full dataset, target <2s to first result

- [ ] **20.14** Implement incremental zone loading (prioritize nearby zones first)

**Story 20 Complete When:**
- [ ] Zone lookup completes in <100ms for 95% of requests
- [ ] App cold start to first result <2 seconds
- [ ] Memory usage stays under 100MB typical usage
- [ ] No UI jank during zone loading or lookup
- [ ] Performance metrics logged for monitoring

---

## Story 21 (S21): Zone Card UI Refinements

**Goal:** Polish zone card appearance and behavior across expanded/minimized states

### Tasks

#### Card Dimensions & Layout
- [x] **21.1** Reduce expanded card height by 20% (miniCardHeight 88→70pt)

- [x] **21.2** Scale zone circle proportionally (56→44pt) for reduced card height

- [x] **21.3** Adjust HStack spacing (16→12pt) for tighter layout

#### Map Zoom Levels
- [x] **21.4** Configure expanded map zoom multiplier (1.3→0.5)

- [x] **21.5** Configure collapsed map zoom multiplier (0.7→0.65)

#### Permit Status Badges
- [x] **21.6** Move PERMIT INVALID badge from minimized card to expanded card

- [x] **21.7** Position PERMIT INVALID badge in top-left corner alongside PERMIT VALID badge

- [x] **21.8** Apply consistent badge styling (gray background for invalid)

#### Zone Circle Colors
- [x] **21.9** Update zone circle on expanded card to use zone-specific color palette

- [x] **21.10** Use ZoneColorProvider.swiftUIColor for consistent zone colors

- [x] **21.11** Apply white text on zone-colored background for all states

#### Card Content Implementation
- [x] **21.12** Implement content areas for "In Permit Zone" state (expanded + minimized)

- [x] **21.13** Implement content areas for "Multi-Permit Zone" state (expanded + minimized)

- [x] **21.14** Implement content areas for "Out of Permit Zone" state (expanded + minimized)

- [x] **21.15** Implement content areas for "Paid Parking" state (expanded + minimized)

- [ ] **21.16** Add time-based information (time until restrictions, street cleaning)

- [x] **21.17** Add enforcement hours display and "Park Until" calculation

- [ ] **21.18** Add distance to nearest valid zone (out of permit zone state)

#### Enforcement-Aware Park Until (Nov 2025)
- [x] **21.19** Add enforcementStartTime, enforcementEndTime, enforcementDays to ViewModel

- [x] **21.20** Calculate Park Until time considering enforcement hours (not just time limit)

- [x] **21.21** Show actual move time including future days (e.g., "Park until Mon 8:00 AM")

- [x] **21.22** Top banner shows "UNLIMITED NOW" when outside enforcement, time limit when active

- [x] **21.23** Mini card title shows "Unlimited Now" or time limit based on enforcement

- [x] **21.24** Hook up ValidityBadgeView on expanded card to use same enforcement-aware logic

#### Address Search Map Pin (Nov 2025)
- [x] **21.25** Add SearchedLocationAnnotation class for address search pin

- [x] **21.26** Show blue pin on map when address search succeeds

- [x] **21.27** Remove pin when returning to GPS location

- [x] **21.28** Fix location timeout when returning from address search (use cached GPS)

**Story 21 Complete When:**
- [x] Expanded card has reduced height with proportional elements
- [x] Map zoom levels tuned for optimal zone visibility
- [x] Permit badges positioned correctly on expanded card
- [x] Zone circles display zone-specific colors
- [x] Content design completed for all four parking states
- [x] Park Until shows enforcement-aware times
- [x] Address search shows pin marker on map

---

## Story 22 (S22): CarPlay Experience Update

**Goal:** Enhance CarPlay integration with improved zone display and interaction

### Tasks

#### Zone Display Improvements
- [ ] **22.1** Update CPInformationTemplate to show state-specific content (valid/invalid/metered)

- [ ] **22.2** Add zone color indicator to CarPlay display

- [ ] **22.3** Show time limit information for out-of-permit zones

- [ ] **22.4** Display metered parking rate and limit info

#### Navigation & Interaction
- [ ] **22.5** Add "Find Parking" button to navigate to nearest valid zone

- [ ] **22.6** Implement zone change alerts with haptic feedback

- [ ] **22.7** Add quick actions for common tasks (save location, start timer)

#### Visual Polish
- [ ] **22.8** Improve CarPlay template styling for better readability while driving

- [ ] **22.9** Add dark mode support for CarPlay display

- [ ] **22.10** Test on CarPlay Simulator and physical unit

**Story 22 Complete When:**
- [ ] CarPlay shows state-specific zone information
- [ ] Zone changes are clearly communicated to driver
- [ ] Quick actions accessible without distraction
- [ ] Tested on physical CarPlay unit

---

## Future Enhancements (Post-Beta)

### Data Coverage Improvements

- [ ] **F1** Add paid/metered parking zones to map data (DataSF meters dataset integration)

- [ ] **F2** Implement city-wide coverage map to distinguish between:
  - RPP zones (current data)
  - Metered/paid parking areas
  - Unregulated street parking
  - Private/no parking areas

- [ ] **F3** Define "unknown area" handling with visual map boundaries showing data coverage

### Additional Cities

- [ ] **F4** Add Oakland RPP zone support
- [ ] **F5** Add Berkeley RPP zone support
- [ ] **F6** Abstract city-specific logic for multi-city scalability

### Parking Experience (Full Feature)

**Goal:** Complete parking session management from arrival to departure

#### Parking Event Detection
- [ ] **F7** Detect parking events (location stationary for >2 minutes after driving)
- [ ] **F8** Save parking location with timestamp, zone info, and address
- [ ] **F9** Auto-detect when user leaves parked car (walking away from location)

#### Active Parking Session
- [ ] **F10** Show active parking session card on home screen
- [ ] **F11** Display elapsed time since parked with live counter
- [ ] **F12** Track parking duration with countdown for time-limited zones
- [ ] **F13** Integrate with meter payment apps (PayByPhone, ParkMobile deep links)
- [ ] **F14-P** Add "I'm leaving" button to end parking session

#### Find My Car
- [ ] **F15-P** Show "Find My Car" button when away from parked location
- [ ] **F16-P** Display walking directions to saved parking location
- [ ] **F17-P** Show distance and estimated walk time to car
- [ ] **F18-P** Add AR view option for finding car in garages

#### Parking History
- [ ] **F19-P** Build parking history view with list of past sessions
- [ ] **F20-P** Filter history by zone, date range, duration
- [ ] **F21-P** Add parking session notes (floor/section for garages, photo of spot)
- [ ] **F22-P** Show statistics (most visited zones, average duration, total time)
- [ ] **F23-P** Export parking history (CSV for expense tracking)

### Detailed Parking Restrictions (Non-RPP)

- [ ] **F14** Integrate street sweeping schedule data (DataSF street sweeping dataset)
- [ ] **F15** Add time-limited parking zones (2-hour, 4-hour limits)
- [ ] **F16** Display meter zones with rate and time limit info
- [ ] **F17** Show tow-away zones with active hours
- [ ] **F18** Add commercial loading zones and restrictions
- [ ] **F19** Display no-parking zones (fire hydrants, driveways, bus stops)
- [ ] **F20** Create unified "parking rules at this spot" view combining all restriction types

### Notification Experience (Full Feature)

**Goal:** Proactive alerts to help users avoid parking violations

*Blocked by: Parking Experience (F7-F23-P)*

#### Move Car Alerts
- [ ] **F-N1** Send push notification before street sweeping at parked location
- [ ] **F-N2** Alert when approaching time limit for time-restricted parking
- [ ] **F-N3** Notify before meter expires (if meter end time was entered)
- [ ] **F-N4** Warn about upcoming tow-away hours at current parking spot

#### Configuration
- [ ] **F-N5** Add configurable notification lead time (15min, 30min, 1hr before)
- [ ] **F-N6** Allow per-notification-type enable/disable settings
- [ ] **F-N7** Set quiet hours (no notifications during sleep time)
- [ ] **F-N8** Configure notification sound and vibration preferences

#### Notification Actions
- [ ] **F-N9** Support "Snooze" action on notifications (remind again in 10min)
- [ ] **F-N10** Add "I moved" action to dismiss and end parking session
- [ ] **F-N11** Add "Navigate to car" action for quick directions
- [ ] **F-N12** Support "Extend meter" deep link to payment app

#### Smart Notifications
- [ ] **F-N13** Learn user patterns (typical parking duration, common zones)
- [ ] **F-N14** Adjust notification timing based on walking distance to car
- [ ] **F-N15** Detect when user is already walking to car (suppress alerts)
- [ ] **F-N16** Send summary notification at end of day (parking stats)

---

## Quick Reference: Prompt Templates

### Starting a Task
```
Implement [task description] for SF Parking Zone Finder following the
architecture in TechnicalArchitecture.md. Use SwiftUI and MVVM pattern.
```

### Continuing Work
```
Continue working on SF Parking Zone Finder. The last completed task was
[X.X]. Now implement [next task description].
```

### Reviewing Progress
```
Show me the current state of [component] in SF Parking Zone Finder and
identify any issues or missing pieces.
```

### Running Tests
```
Run the unit tests for [module] and fix any failures.
```

---

## Notes

- Check off tasks as completed by changing `[ ]` to `[x]`
- Update Progress Summary counts after completing milestones
- Tasks are designed to be independent prompts but should be done in order within each milestone
- Milestones 1-6 are critical path; 7-9 can partially parallel after M6 starts
- Each task prompt can be customized with additional context as needed

---

**Last Updated:** November 2025
**Related Docs:** TechnicalArchitecture.md, EngineeringProjectPlan.md
