# SF Parking Zone Finder - Implementation Checklist

**Purpose:** Actionable task list for prompting Claude Code to build the app
**Usage:** Copy each task as a prompt, check off when complete

---

## Progress Summary

### 🎯 Minimum Viable Alpha Path

For a functional Alpha release with real data, complete these in order:
1. ✅ S1-S9: iOS app core features (DONE)
2. ✅ S10: Data Pipeline (DONE)
3. 🔲 **S12: iOS Data Integration** - Bundle real pipeline data into app
4. 🔲 S13: Backend Testing - Verify everything works

**Optional for Alpha (can defer to Beta):**
- S11: Backend API - Only needed for dynamic data updates

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
| S11: Backend API | Not Started | 0/7 |
| S12: iOS Data Integration | In Progress | 5/9 |
| S13: Backend Testing | In Progress | 2/6 |

**Alpha Progress:** 95/102 tasks complete (93%)

### 🎯 Epic: Beta Release

| Story | Status | Tasks |
|-------|--------|-------|
| S14: Error Handling | Not Started | 0/5 |
| S15: UI Polish & Animations | Not Started | 0/8 |
| S16: CarPlay Support | Not Started | 0/10 |
| S17: Map Zone Boundaries | Not Started | 0/19 |
| S18: Beta Release Prep | Not Started | 0/6 |
| S19: UI Testing | Not Started | 0/8 |

**Beta Progress:** 0/56 tasks complete (0%)

---

**Overall Progress:** 95/158 tasks complete (60%)

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

## Story 11 (S11): Backend API

**Goal:** REST API service to serve zone and parking rule data

### Tasks

- [ ] **15.1** Set up PostgreSQL + PostGIS database with spatial indexes

- [ ] **15.2** Implement database schema (cities, zones, rules, data_versions tables)

- [ ] **15.3** Create FastAPI service with zone lookup endpoint (POST /lookup)

- [ ] **15.4** Implement spatial queries using PostGIS (point-in-polygon)

- [ ] **15.5** Add Redis caching layer for zone data and lookup results

- [ ] **15.6** Implement API rate limiting and API key authentication

- [ ] **15.7** Deploy to cloud infrastructure (AWS/GCP with auto-scaling)

**Story Complete When:**
- [ ] API returns correct zones for test coordinates
- [ ] Response time < 200ms (p95)
- [ ] Rate limiting enforced
- [ ] Deployed and accessible from iOS app

---

## Story 12 (S12): iOS Data Integration (Static Bundle)

**Goal:** iOS app uses real parking data from pipeline output (bundled at build time)

### Tasks

- [x] **12.1** Create conversion script: pipeline output → iOS-compatible GeoJSON schema

- [x] **12.2** Update LocalZoneDataSource to load official parking_zones.json instead of mock data

- [ ] **12.3** Run pipeline on machine with network access, generate parking_data.json

- [ ] **12.4** Bundle pipeline output JSON into iOS app Resources folder

- [x] **12.5** Display data version and "last updated" in Settings/About

- [x] **12.6** Add data source attribution (DataSF, SFMTA) in About screen

- [x] **12.7** Create update script to refresh bundled data from pipeline output

- [ ] **12.8** Test iOS app loads and displays real zone data correctly

- [ ] **12.9** Verify point-in-polygon lookup works with official zone boundaries

**Story 12 Complete When:**
- [ ] iOS app displays real SF parking zone data
- [ ] Zone lookup returns accurate results for test locations
- [ ] Data source/version visible in Settings
- [ ] Process documented for updating bundled data

---

## Story 13 (S13): Backend Testing

**Goal:** Comprehensive test coverage for backend services and integration

### Tasks

- [x] **14.1** Write unit tests for Data Pipeline ETL components

- [x] **14.2** Write integration tests for DataSF and SFMTA API fetchers

- [ ] **14.3** Write unit tests for Backend API endpoints

- [ ] **14.4** Write integration tests for PostGIS spatial queries

- [ ] **14.5** Write end-to-end tests for iOS ↔ Backend communication

- [ ] **14.6** Set up CI/CD pipeline with automated test runs

**Story 14 Complete When:**
- [ ] All backend unit tests pass
- [ ] Integration tests validate data pipeline
- [ ] E2E tests confirm iOS app works with live backend

---

# Beta Release

## Story 14 (S14): Error Handling

**Goal:** Graceful error states with clear user guidance

### Tasks

- [ ] **14.1** Create LocationDeniedView with explanation and button to open Settings app

- [ ] **14.2** Create LocationUnavailableView for GPS timeout scenarios with retry button

- [ ] **14.3** Create OutsideCoverageView shown when user is not in any supported zone

- [ ] **14.4** Create DataLoadingErrorView for mock data parsing failures

- [ ] **14.5** Integrate error views into MainResultView based on state

**Story 14 Complete When:**
- [ ] All error scenarios show appropriate message
- [ ] Error views have actionable next steps
- [ ] Users can recover from errors easily

---

## Story 15 (S15): UI Polish & Animations

**Goal:** Enhanced visual polish and delightful user experience

### Tasks

- [ ] **15.1** Update deprecated Map initializers to iOS 17+ MapContentBuilder syntax

- [ ] **15.2** Add AccentColor to Assets.xcassets with appropriate light/dark variants

- [ ] **15.3** Improve floating map positioning and responsiveness

- [ ] **15.4** Add smooth animations for state transitions (loading, error, success)

- [ ] **15.5** Implement skeleton loading states for zone information

- [ ] **15.6** Polish typography hierarchy and spacing consistency

- [ ] **15.7** Add subtle haptic feedback for user interactions

- [ ] **15.8** Implement Reduce Motion support checking accessibilityReduceMotion

**Story 15 Complete When:**
- [ ] No deprecation warnings in codebase
- [ ] Consistent visual polish throughout app
- [ ] Smooth, delightful animations
- [ ] Full accessibility support

---

## Story 16 (S16): CarPlay Support

**Goal:** Allow drivers to check parking zone status via CarPlay dashboard

### Tasks

- [ ] **16.1** Add CarPlay entitlement and configure Info.plist

- [ ] **16.2** Create CarPlaySceneDelegate to handle CarPlay connection

- [ ] **16.3** Implement CPTemplate-based UI showing current zone and validity

- [ ] **16.4** Create CPPointOfInterestTemplate for zone display

- [ ] **16.5** Add CPMapTemplate with current location and zone overlay

- [ ] **16.6** Implement automatic zone updates while driving

- [ ] **16.7** Add voice feedback option for zone changes (using AVSpeechSynthesizer)

- [ ] **16.8** Handle CarPlay connect/disconnect lifecycle

- [ ] **16.9** Test on CarPlay Simulator and physical CarPlay unit

- [ ] **16.10** Add CarPlay support documentation

**Story 16 Complete When:**
- [ ] App appears in CarPlay dashboard
- [ ] Zone status visible while driving
- [ ] Updates automatically as location changes
- [ ] Voice feedback announces zone changes

---

## Story 17 (S17): Map Zone Boundaries

**Goal:** Display parking zone boundaries as visual polygons on the expanded map view

### Tasks

#### Zone Boundary Display
- [ ] **17.1** Create ZoneOverlay model with polygon coordinates compatible with both MapKit and Google Maps

- [ ] **17.2** Implement zone polygon overlays for each parking zone from mock data boundaries

- [ ] **17.3** Add overlay renderer to style zone polygons with semi-transparent fill and border

- [ ] **17.4** Style current zone with accent color fill (20% opacity) and thick border

- [ ] **17.5** Style adjacent/nearby zones with lighter differentiated colors

- [ ] **17.6** Calculate zone polygon centroids and add zone label annotations (large, bold letters)

- [ ] **17.7** Implement tap gesture on zone overlays to show ZoneInfoCard popup

- [ ] **17.8** Create ZoneInfoCard popup view with zone name, type, basic rules, and "View Details" button

#### Zone Color System
- [ ] **17.9** Define distinct color palette for all RPP zones (A-Z, AA-LL) with good visual differentiation

- [ ] **17.10** Create ZoneColorProvider service that maps zone codes to SwiftUI/UIKit colors

- [ ] **17.11** Store zone colors in data model or configuration (support both light/dark mode variants)

- [ ] **17.12** Implement color-coded polygon overlays on expanded map view (full screen only)

- [ ] **17.13** Add legend or key showing zone colors (optional, toggleable)

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
