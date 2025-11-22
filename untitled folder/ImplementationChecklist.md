# SF Parking Zone Finder - Implementation Checklist

**Purpose:** Actionable task list for prompting Claude Code to build the app
**Usage:** Copy each task as a prompt, check off when complete

---

## Progress Summary

| Milestone | Status | Tasks |
|-----------|--------|-------|
| M1: Project Foundation | Not Started | 0/12 |
| M2: Data Layer | Not Started | 0/8 |
| M3: Location Services | Not Started | 0/6 |
| M4: Zone Lookup Engine | Not Started | 0/8 |
| M5: Rule Interpretation | Not Started | 0/6 |
| M6: Main Result View | Not Started | 0/14 |
| M7: Floating Map | Not Started | 0/10 |
| M8: Onboarding Flow | Not Started | 0/10 |
| M9: Settings Screen | Not Started | 0/8 |
| M10: Error Handling & Polish | Not Started | 0/8 |
| M11: Testing | Not Started | 0/8 |
| M12: Beta Release | Not Started | 0/6 |

**Overall Progress:** 0/104 tasks complete

---

## Milestone 1: Project Foundation

**Goal:** Xcode project set up with dependencies and base architecture

### Tasks

- [ ] **1.1** Create a new Xcode project for SF Parking Zone Finder using SwiftUI App template, targeting iOS 16+, with the folder structure defined in TechnicalArchitecture.md

- [ ] **1.2** Add Google Maps SDK for iOS as a Swift Package dependency and configure the API key in AppDelegate

- [ ] **1.3** Create the DependencyContainer class with protocol-based service registration for dependency injection

- [ ] **1.4** Define all service protocols: ZoneServiceProtocol, ZoneDataSourceProtocol, LocationServiceProtocol, MapProviderProtocol, ReverseGeocodingServiceProtocol, RulInterpreterProtocol, ZoneLookupEngineProtocol

- [ ] **1.5** Create the core data models: CityIdentifier, ParkingZone, ParkingRule, Coordinate, ZoneType, ZoneMetadata, DataAccuracy

- [ ] **1.6** Create the permit data models: ParkingPermit, PermitType

- [ ] **1.7** Create the result models: ZoneLookupResult, LookupConfidence, RuleInterpretationResult, PermitValidityStatus, ConditionalFlag

- [ ] **1.8** Create the Address model for reverse geocoding results

- [ ] **1.9** Set up the app entry point (SFParkingZoneFinderApp.swift) with dependency container initialization

- [ ] **1.10** Create Color+Theme extension with app color definitions for validity statuses (valid green, invalid red, conditional yellow, etc.)

- [ ] **1.11** Add .gitignore entries for Xcode, Swift, and sensitive files (API keys)

- [ ] **1.12** Create a basic README.md with project setup instructions

**Milestone 1 Complete When:**
- [ ] Project builds without errors
- [ ] Google Maps SDK initializes (map view renders)
- [ ] All protocols and models compile

---

## Milestone 2: Data Layer

**Goal:** Mock parking zone data loads and parses correctly

### Tasks

- [ ] **2.1** Create the mock data file sf_parking_zones.json with the schema defined in TechnicalArchitecture.md, including 10-15 sample SF parking zones covering Areas Q, R, A, and some metered zones

- [ ] **2.2** Implement GeoJSONParser to parse sf_parking_zones.json into ParkingZone model arrays

- [ ] **2.3** Implement LocalZoneDataSource conforming to ZoneDataSourceProtocol that loads zones from the bundled JSON file

- [ ] **2.4** Implement ZoneCache with in-memory storage for loaded zones

- [ ] **2.5** Implement ZoneRepository that coordinates between ZoneCache and LocalZoneDataSource

- [ ] **2.6** Register data layer services in DependencyContainer

- [ ] **2.7** Write unit tests for GeoJSONParser covering valid JSON, invalid JSON, and missing fields

- [ ] **2.8** Write unit tests for LocalZoneDataSource verifying zones load correctly

**Milestone 2 Complete When:**
- [ ] sf_parking_zones.json contains valid sample data for SF
- [ ] Calling ZoneRepository.getZones() returns parsed ParkingZone array
- [ ] Unit tests pass

---

## Milestone 3: Location Services

**Goal:** App can acquire device location and reverse geocode to address

### Tasks

- [ ] **3.1** Implement LocationService wrapping CLLocationManager with authorization handling, conforming to LocationServiceProtocol

- [ ] **3.2** Add requestSingleLocation() async method that returns CLLocation or throws error with timeout handling

- [ ] **3.3** Add location accuracy indicator logic to LocationService

- [ ] **3.4** Implement ReverseGeocodingService using CLGeocoder with address caching

- [ ] **3.5** Register location services in DependencyContainer

- [ ] **3.6** Write unit tests for LocationService using mock CLLocationManager

**Milestone 3 Complete When:**
- [ ] App requests location permission correctly
- [ ] LocationService returns device coordinates
- [ ] ReverseGeocodingService returns formatted address
- [ ] Unit tests pass

---

## Milestone 4: Zone Lookup Engine

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

**Milestone 4 Complete When:**
- [ ] findZone(at:) returns correct zone for test coordinates
- [ ] Boundary cases default to most restrictive zone
- [ ] Overlapping zones all returned in result
- [ ] Unit tests pass with >90% coverage

---

## Milestone 5: Rule Interpretation Engine

**Goal:** Determine permit validity and generate human-readable rule summaries

### Tasks

- [ ] **5.1** Implement RuleInterpreter conforming to RuleInterpreterProtocol with interpretRules(for:userPermits:at:) method

- [ ] **5.2** Implement permit matching logic that compares user permits against zone's validPermitAreas

- [ ] **5.3** Implement PermitValidityStatus determination (valid, invalid, conditional, noPermitRequired, multipleApply)

- [ ] **5.4** Implement generateRuleSummary() that creates human-readable bullet points from ParkingRule array

- [ ] **5.5** Add conditional flag identification that marks time-based restrictions as display-only

- [ ] **5.6** Write unit tests for RuleInterpreter covering all validity statuses and edge cases

**Milestone 5 Complete When:**
- [ ] interpretRules() returns correct validity for all permit scenarios
- [ ] Rule summaries are readable and accurate
- [ ] Conditional rules flagged but not enforced
- [ ] Unit tests pass with >90% coverage

---

## Milestone 6: Main Result View (Primary UI)

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

**Milestone 6 Complete When:**
- [ ] Main screen shows zone name, validity badge, and rules
- [ ] Overlapping zones display correctly
- [ ] Pull to refresh works
- [ ] VoiceOver reads all content correctly
- [ ] Dynamic Type scales properly

---

## Milestone 7: Floating Map Component

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

**Milestone 7 Complete When:**
- [ ] Floating map renders at correct size and position
- [ ] User location dot visible on map
- [ ] Current zone boundary drawn on map
- [ ] Tap expands to full-screen map
- [ ] Full-screen map shows all nearby zones
- [ ] Back button returns to result view

---

## Milestone 8: Onboarding Flow

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

**Milestone 8 Complete When:**
- [ ] New user sees welcome screen on first launch
- [ ] Location permission requested with explanation
- [ ] User can select multiple permit areas
- [ ] Permits saved and persist across launches
- [ ] Onboarding completes and shows main view
- [ ] Returning users skip directly to main view

---

## Milestone 9: Settings Screen

**Goal:** User can manage permits and preferences

### Tasks

- [ ] **9.1** Create SettingsViewModel managing user preferences and permit data

- [ ] **9.2** Create PermitManagementView listing current permits with add/edit/delete functionality

- [ ] **9.3** Create AddPermitView for adding new permits (reuse PermitAreaGrid)

- [ ] **9.4** Add map preferences section: toggle floating map visibility, map position picker, map style picker

- [ ] **9.5** Create AboutView showing app version, data version, privacy policy, and open source licenses

- [ ] **9.6** Add Help section with FAQ placeholder, report issue email link, and rate app link

- [ ] **9.7** Assemble SettingsView with all sections using List and NavigationLink

- [ ] **9.8** Add settings gear icon to MainResultView navigation bar linking to SettingsView

**Milestone 9 Complete When:**
- [ ] Settings accessible from main view
- [ ] User can add, edit, delete permits
- [ ] Map preferences persist and apply
- [ ] About information displays correctly

---

## Milestone 10: Error Handling & Polish

**Goal:** Graceful error states and UI polish

### Tasks

- [ ] **10.1** Create LocationDeniedView with explanation and button to open Settings app

- [ ] **10.2** Create LocationUnavailableView for GPS timeout scenarios with retry button

- [ ] **10.3** Create OutsideCoverageView shown when user is not in any supported zone

- [ ] **10.4** Create DataLoadingErrorView for mock data parsing failures

- [ ] **10.5** Integrate error views into MainResultView based on state

- [ ] **10.6** Add haptic feedback for validity status changes and refresh completion

- [ ] **10.7** Implement Reduce Motion support checking accessibilityReduceMotion environment value

- [ ] **10.8** Polish all views for visual consistency: spacing, typography, colors

**Milestone 10 Complete When:**
- [ ] All error scenarios show appropriate message
- [ ] Error views have actionable next steps
- [ ] Reduce Motion preference respected
- [ ] UI is visually polished and consistent

---

## Milestone 11: Testing

**Goal:** Comprehensive test coverage for core functionality

### Tasks

- [ ] **11.1** Achieve >90% unit test coverage for ZoneLookupEngine

- [ ] **11.2** Achieve >90% unit test coverage for RuleInterpreter

- [ ] **11.3** Write unit tests for PermitService (save, load, delete, primary permit)

- [ ] **11.4** Write unit tests for MainResultViewModel

- [ ] **11.5** Create UI test for complete onboarding flow

- [ ] **11.6** Create UI test for main result view displaying zone correctly

- [ ] **11.7** Create UI test for map expand and collapse

- [ ] **11.8** Create UI test for settings permit management

**Milestone 11 Complete When:**
- [ ] All unit tests pass
- [ ] Core business logic has >80% coverage
- [ ] UI tests pass for critical flows

---

## Milestone 12: Beta Release Prep

**Goal:** App ready for TestFlight distribution

### Tasks

- [ ] **12.1** Configure App Store Connect: create app record, set bundle ID, configure app information

- [ ] **12.2** Add app icons for all required sizes

- [ ] **12.3** Create launch screen / splash screen

- [ ] **12.4** Write privacy policy and add to app / settings

- [ ] **12.5** Archive build and upload to TestFlight

- [ ] **12.6** Distribute to beta testers (target: 50+ SF residents)

**Milestone 12 Complete When:**
- [ ] App available on TestFlight
- [ ] Beta testers can install and use app
- [ ] No crash on launch for any tester
- [ ] Feedback collection mechanism in place

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
