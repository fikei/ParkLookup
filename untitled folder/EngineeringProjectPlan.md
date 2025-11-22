# Engineering Project Plan: SF Parking Zone Finder

**Version:** 1.0
**Last Updated:** November 2025
**Status:** Draft
**Authors:** Engineering Team

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Phased Implementation Roadmap](#phased-implementation-roadmap)
3. [Milestones & Deliverables](#milestones--deliverables)
4. [Epics, User Stories & Tasks](#epics-user-stories--tasks)
5. [Dependencies](#dependencies)
6. [Risks & Mitigation](#risks--mitigation)
7. [Test Plan](#test-plan)
8. [Definition of Done](#definition-of-done)

---

## Executive Summary

This document outlines the engineering implementation plan for SF Parking Zone Finder, progressing from MVP through V1.1 and V2. The plan is organized into phases with clear milestones, deliverables, and acceptance criteria.

### Release Timeline Overview

| Phase | Version | Scope | Key Milestone |
|-------|---------|-------|---------------|
| **Phase 1** | MVP (V1.0) | Core functionality, SF only, mock data | TestFlight Beta |
| **Phase 2** | V1.1 | Polish, real-time location, parking timer | App Store Launch |
| **Phase 3** | V2.0 | Backend integration, multi-city, Android | Platform Expansion |

---

## Phased Implementation Roadmap

### Phase 1: MVP (V1.0)

**Goal:** Deliver a functional iOS app that answers "Can I park here?" for San Francisco using embedded mock data.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PHASE 1: MVP                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Sprint 1          Sprint 2          Sprint 3          Sprint 4     │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐      ┌──────────┐ │
│  │ Project  │      │  Core    │      │   Map    │      │  Polish  │ │
│  │  Setup   │ ───► │  Flow    │ ───► │  & UX    │ ───► │  & Beta  │ │
│  │          │      │          │      │          │      │          │ │
│  └──────────┘      └──────────┘      └──────────┘      └──────────┘ │
│                                                                      │
│  Deliverables:                                                       │
│  - Project scaffold        - Zone lookup works    - Floating map    │
│  - Mock data loaded        - Permit validation    - Full-screen map │
│  - Location service        - Main result view     - Settings screen │
│  - CI pipeline stub        - Onboarding flow      - TestFlight beta │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Sprint Breakdown (MVP)

| Sprint | Focus | Deliverables |
|--------|-------|--------------|
| **Sprint 1** | Project Setup & Foundation | Xcode project, dependencies, mock data parser, location service |
| **Sprint 2** | Core Business Logic | Zone lookup engine, rule interpreter, permit service, main result view |
| **Sprint 3** | Map & Enhanced UX | Google Maps integration, floating/expanded map, onboarding flow |
| **Sprint 4** | Polish & Beta Release | Settings, error handling, accessibility, TestFlight beta |

---

### Phase 2: V1.1 (Post-MVP Enhancements)

**Goal:** Polish based on beta feedback, add real-time location tracking and parking timer.

```
┌─────────────────────────────────────────────────────────────────────┐
│                       PHASE 2: V1.1                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Sprint 5          Sprint 6          Sprint 7                       │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐                   │
│  │  Beta    │      │  Real-   │      │   App    │                   │
│  │ Feedback │ ───► │  time &  │ ───► │  Store   │                   │
│  │  Fixes   │      │  Timer   │      │ Release  │                   │
│  └──────────┘      └──────────┘      └──────────┘                   │
│                                                                      │
│  Deliverables:                                                       │
│  - Bug fixes              - Auto location refresh   - App Store     │
│  - UX improvements        - Parking timer          - Press kit      │
│  - Boundary refinement    - Enhanced accessibility - Support docs   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Sprint Breakdown (V1.1)

| Sprint | Focus | Deliverables |
|--------|-------|--------------|
| **Sprint 5** | Beta Feedback & Fixes | Bug fixes, UX refinements, boundary algorithm improvements |
| **Sprint 6** | Real-time & Timer | Auto-refresh on movement, parking timer with notifications |
| **Sprint 7** | App Store Release | Final QA, App Store submission, marketing assets |

---

### Phase 3: V2.0 (Backend & Expansion)

**Goal:** Integrate backend API, enable multi-city support, begin Android development.

```
┌─────────────────────────────────────────────────────────────────────┐
│                       PHASE 3: V2.0                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Sprint 8-9        Sprint 10-11      Sprint 12-13                   │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐                   │
│  │ Backend  │      │  Multi-  │      │ Android  │                   │
│  │  Integ   │ ───► │  City    │ ───► │   MVP    │                   │
│  │          │      │          │      │          │                   │
│  └──────────┘      └──────────┘      └──────────┘                   │
│                                                                      │
│  Deliverables:                                                       │
│  - Backend API live       - Oakland, Berkeley    - Android app v1   │
│  - Remote data sync       - City switcher UI     - Feature parity   │
│  - Offline caching        - Localized data       - Play Store       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Sprint Breakdown (V2.0)

| Sprint | Focus | Deliverables |
|--------|-------|--------------|
| **Sprint 8-9** | Backend Integration | API client, remote data source, offline caching, data sync |
| **Sprint 10-11** | Multi-City Support | Oakland & Berkeley data, city selection UI, location-based city detection |
| **Sprint 12-13** | Android MVP | Kotlin/Compose Android app, Google Maps integration, Play Store launch |

---

## Milestones & Deliverables

### MVP Milestones

| Milestone | Description | Deliverables | Exit Criteria |
|-----------|-------------|--------------|---------------|
| **M1: Foundation Complete** | Project setup and data layer functional | Xcode project, mock data loads, location service works | Unit tests pass, data displayed in debug view |
| **M2: Core Flow Complete** | Zone lookup and permit validation working | Zone lookup engine, rule interpreter, main result view | Can determine permit validity at any SF coordinate |
| **M3: Map Integration Complete** | Floating and expanded maps functional | Google Maps SDK integrated, floating widget, full-screen map | Map shows user location and zone boundaries |
| **M4: Onboarding Complete** | First-launch flow implemented | Welcome, permissions, permit setup, tutorial | New user can complete onboarding and see results |
| **M5: Settings Complete** | User preferences manageable | Settings screen, permit management, about section | User can add/edit permits, change map preferences |
| **M6: Beta Ready** | App ready for TestFlight | All MVP features, basic error handling, accessibility | QA sign-off, no P0/P1 bugs, TestFlight build uploaded |

### V1.1 Milestones

| Milestone | Description | Deliverables | Exit Criteria |
|-----------|-------------|--------------|---------------|
| **M7: Beta Feedback Addressed** | Critical issues from beta resolved | Bug fixes, UX improvements | Beta testers report satisfaction, crash-free rate >99% |
| **M8: Real-time Location** | Auto-refresh when user moves | Background location updates, zone change detection | Zone updates automatically when crossing boundaries |
| **M9: Parking Timer** | Timer for time-limited zones | Timer UI, local notifications | User receives alert before time expires |
| **M10: App Store Launch** | Public release | App Store listing, screenshots, description | App approved and live on App Store |

### V2.0 Milestones

| Milestone | Description | Deliverables | Exit Criteria |
|-----------|-------------|--------------|---------------|
| **M11: Backend Live** | Backend API deployed and integrated | API endpoints, iOS client updated | iOS app uses remote data with offline fallback |
| **M12: Multi-City** | Oakland and Berkeley supported | City data, city switcher UI | Users in Oakland/Berkeley see correct zone data |
| **M13: Android Launch** | Android app on Play Store | Kotlin/Compose app, Play Store listing | Android app achieves feature parity with iOS V1.1 |

---

## Epics, User Stories & Tasks

### Epic 1: Project Foundation

**Goal:** Establish project infrastructure, dependencies, and base architecture.

#### User Stories

**US1.1: As a developer, I can build and run the project so that I can begin development.**

| Task | Description | Estimate |
|------|-------------|----------|
| T1.1.1 | Create Xcode project with SwiftUI App template | S |
| T1.1.2 | Configure minimum deployment target (iOS 16) | S |
| T1.1.3 | Set up folder structure per architecture doc | S |
| T1.1.4 | Add .gitignore and configure Git repository | S |
| T1.1.5 | Create README with setup instructions | S |

**US1.2: As a developer, I can use Google Maps SDK so that maps render correctly.**

| Task | Description | Estimate |
|------|-------------|----------|
| T1.2.1 | Register for Google Maps API key | S |
| T1.2.2 | Add Google Maps SDK via Swift Package Manager | S |
| T1.2.3 | Configure API key in AppDelegate | S |
| T1.2.4 | Create GoogleMapsViewRepresentable wrapper | M |
| T1.2.5 | Verify map renders in test view | S |

**US1.3: As a developer, I have a dependency injection container so services are testable.**

| Task | Description | Estimate |
|------|-------------|----------|
| T1.3.1 | Create DependencyContainer class | S |
| T1.3.2 | Define service protocols (ZoneServiceProtocol, etc.) | M |
| T1.3.3 | Register concrete implementations | S |
| T1.3.4 | Create mock implementations for testing | M |

**US1.4: As a developer, CI runs tests automatically so code quality is maintained.**

| Task | Description | Estimate |
|------|-------------|----------|
| T1.4.1 | Create placeholder CI configuration file | S |
| T1.4.2 | Document CI setup requirements for future | S |

> **Note:** Full CI/CD implementation deferred; placeholder created.

---

### Epic 2: Data Layer

**Goal:** Load, parse, and cache parking zone data from embedded JSON.

#### User Stories

**US2.1: As the app, I can load mock zone data so users see parking information.**

| Task | Description | Estimate |
|------|-------------|----------|
| T2.1.1 | Create sf_parking_zones.json with sample data | L |
| T2.1.2 | Define ParkingZone, ParkingRule, Coordinate models | M |
| T2.1.3 | Implement GeoJSONParser to parse mock data | M |
| T2.1.4 | Create LocalZoneDataSource implementation | M |
| T2.1.5 | Write unit tests for data parsing | M |

**US2.2: As the app, I cache loaded zones in memory so lookups are fast.**

| Task | Description | Estimate |
|------|-------------|----------|
| T2.2.1 | Implement ZoneCache with in-memory storage | S |
| T2.2.2 | Add cache invalidation logic | S |
| T2.2.3 | Create ZoneRepository coordinating cache and source | M |
| T2.2.4 | Write unit tests for caching behavior | S |

---

### Epic 3: Location Services

**Goal:** Acquire user location and convert to human-readable address.

#### User Stories

**US3.1: As a user, I can see my current location so the app knows where I am.**

| Task | Description | Estimate |
|------|-------------|----------|
| T3.1.1 | Implement LocationService wrapping CLLocationManager | M |
| T3.1.2 | Handle authorization status changes | M |
| T3.1.3 | Implement requestSingleLocation() async method | M |
| T3.1.4 | Add location accuracy indicator logic | S |
| T3.1.5 | Write unit tests with mock location data | M |

**US3.2: As a user, I see my current address so I know where I am.**

| Task | Description | Estimate |
|------|-------------|----------|
| T3.2.1 | Implement ReverseGeocodingService using CLGeocoder | M |
| T3.2.2 | Add address caching to avoid repeated API calls | S |
| T3.2.3 | Format address for display | S |
| T3.2.4 | Handle geocoding errors gracefully | S |

---

### Epic 4: Zone Lookup Engine

**Goal:** Determine which parking zone contains a given GPS coordinate.

#### User Stories

**US4.1: As a user, I see the correct parking zone for my location.**

| Task | Description | Estimate |
|------|-------------|----------|
| T4.1.1 | Implement point-in-polygon algorithm | M |
| T4.1.2 | Create SpatialIndex for efficient polygon queries | L |
| T4.1.3 | Implement ZoneLookupEngine with findZone() method | M |
| T4.1.4 | Handle multiple overlapping zones (show all) | M |
| T4.1.5 | Implement boundary handling (default to restrictive) | M |
| T4.1.6 | Add lookup confidence scoring | S |
| T4.1.7 | Write comprehensive unit tests | L |

**US4.2: As a user, when I'm at a zone boundary, I see all applicable zones.**

| Task | Description | Estimate |
|------|-------------|----------|
| T4.2.1 | Detect when user is within boundary threshold | M |
| T4.2.2 | Return all overlapping zones in result | S |
| T4.2.3 | Sort zones by restrictiveness | S |
| T4.2.4 | Log boundary encounters for debugging | S |

---

### Epic 5: Rule Interpretation Engine

**Goal:** Determine permit validity and generate human-readable rule summaries.

#### User Stories

**US5.1: As a user, I know if my permit is valid at my current location.**

| Task | Description | Estimate |
|------|-------------|----------|
| T5.1.1 | Implement RuleInterpreter with interpretRules() method | M |
| T5.1.2 | Match user permits against zone valid permits | M |
| T5.1.3 | Determine PermitValidityStatus (valid/invalid/etc.) | M |
| T5.1.4 | Handle multiple matching permits | S |
| T5.1.5 | Write unit tests for all validity scenarios | L |

**US5.2: As a user, I see a clear summary of parking rules.**

| Task | Description | Estimate |
|------|-------------|----------|
| T5.2.1 | Implement generateRuleSummary() function | M |
| T5.2.2 | Format enforcement hours in human-readable form | S |
| T5.2.3 | Include street cleaning warnings when applicable | S |
| T5.2.4 | Flag conditional rules (display only, not enforced) | S |

---

### Epic 6: Main Result View (Primary UI)

**Goal:** Display parking zone status, permit validity, and rules in a full-screen text view.

#### User Stories

**US6.1: As a user, I see the zone name prominently displayed.**

| Task | Description | Estimate |
|------|-------------|----------|
| T6.1.1 | Create ZoneStatusCardView component | M |
| T6.1.2 | Style zone name with large, bold typography | S |
| T6.1.3 | Support Dynamic Type for accessibility | S |

**US6.2: As a user, I see a clear YES/NO indicator for permit validity.**

| Task | Description | Estimate |
|------|-------------|----------|
| T6.2.1 | Create ValidityBadgeView component | M |
| T6.2.2 | Implement color coding (green/red/yellow/gray/blue) | S |
| T6.2.3 | Add shape indicators for color-blind accessibility | S |
| T6.2.4 | Write accessibility labels for VoiceOver | S |

**US6.3: As a user, I see a summary of parking rules.**

| Task | Description | Estimate |
|------|-------------|----------|
| T6.3.1 | Create RulesSummaryView component | M |
| T6.3.2 | Display rules as bullet points | S |
| T6.3.3 | Add "View Full Rules" expandable section | M |
| T6.3.4 | Display warnings (street cleaning, etc.) | S |

**US6.4: As a user, I see all applicable zones when multiple overlap.**

| Task | Description | Estimate |
|------|-------------|----------|
| T6.4.1 | Create OverlappingZonesView component | M |
| T6.4.2 | Show validity status for each zone | S |
| T6.4.3 | Indicate which rules are being displayed | S |

**US6.5: As a user, I see additional info (address, last updated, refresh).**

| Task | Description | Estimate |
|------|-------------|----------|
| T6.5.1 | Create AdditionalInfoView component | M |
| T6.5.2 | Display current address from reverse geocoding | S |
| T6.5.3 | Add "Refresh Location" button | S |
| T6.5.4 | Add "Report Issue" link | S |
| T6.5.5 | Show last updated timestamp | S |

**US6.6: As a user, I can pull to refresh my location.**

| Task | Description | Estimate |
|------|-------------|----------|
| T6.6.1 | Implement pull-to-refresh on ScrollView | S |
| T6.6.2 | Trigger location refresh and zone lookup | S |
| T6.6.3 | Show loading indicator during refresh | S |

---

### Epic 7: Floating Map Component

**Goal:** Provide spatial context through minimized map with expansion capability.

#### User Stories

**US7.1: As a user, I see a small floating map showing my location and zone.**

| Task | Description | Estimate |
|------|-------------|----------|
| T7.1.1 | Create MinimizedMapView (120x120pt) | M |
| T7.1.2 | Show user location dot on map | S |
| T7.1.3 | Show current zone boundary polygon | M |
| T7.1.4 | Apply styling (rounded corners, shadow) | S |
| T7.1.5 | Position map as floating overlay | M |

**US7.2: As a user, I can tap the floating map to expand it full-screen.**

| Task | Description | Estimate |
|------|-------------|----------|
| T7.2.1 | Create ExpandedMapView (full-screen) | L |
| T7.2.2 | Add "Back to Results" button | S |
| T7.2.3 | Show all nearby zones with color coding | M |
| T7.2.4 | Enable pan and zoom gestures | S |
| T7.2.5 | Show zone info card when zone tapped | M |
| T7.2.6 | Implement smooth transition animation | M |

**US7.3: As a user, I can customize the floating map position.**

| Task | Description | Estimate |
|------|-------------|----------|
| T7.3.1 | Add map position preference to settings | S |
| T7.3.2 | Support top-left, top-right, bottom-right | S |
| T7.3.3 | Persist preference to UserDefaults | S |

---

### Epic 8: Onboarding Flow

**Goal:** Guide new users through permissions and permit setup.

#### User Stories

**US8.1: As a new user, I see a welcome screen explaining the app.**

| Task | Description | Estimate |
|------|-------------|----------|
| T8.1.1 | Create WelcomeView with app branding | M |
| T8.1.2 | Add tagline and brief explanation | S |
| T8.1.3 | Add illustration of main result screen | M |
| T8.1.4 | Add "Get Started" button | S |

**US8.2: As a new user, I'm prompted for location permission with clear explanation.**

| Task | Description | Estimate |
|------|-------------|----------|
| T8.2.1 | Create LocationPermissionView | M |
| T8.2.2 | Explain why location is needed | S |
| T8.2.3 | Add privacy note about local-only processing | S |
| T8.2.4 | Handle permission denial gracefully | M |
| T8.2.5 | Show option to open Settings if denied | S |

**US8.3: As a new user, I can enter my parking permits.**

| Task | Description | Estimate |
|------|-------------|----------|
| T8.3.1 | Create PermitSetupView | L |
| T8.3.2 | Create PermitTypePicker (RPP, future types) | M |
| T8.3.3 | Create PermitAreaGrid for area selection | M |
| T8.3.4 | Support multi-permit selection | S |
| T8.3.5 | Save permits to UserDefaults | S |
| T8.3.6 | Add "Skip for now" option | S |

**US8.4: As a new user, I can optionally see a brief tutorial.**

| Task | Description | Estimate |
|------|-------------|----------|
| T8.4.1 | Create TutorialOverlayView (2-3 screens) | M |
| T8.4.2 | Show how to read result screen | S |
| T8.4.3 | Show how to expand map | S |
| T8.4.4 | Add "Got it" / "Skip" buttons | S |
| T8.4.5 | Persist "tutorial seen" flag | S |

---

### Epic 9: Settings Screen

**Goal:** Allow users to manage permits and preferences.

#### User Stories

**US9.1: As a user, I can add, edit, and remove my permits.**

| Task | Description | Estimate |
|------|-------------|----------|
| T9.1.1 | Create PermitManagementView | M |
| T9.1.2 | List current permits with edit/delete | M |
| T9.1.3 | Add "Add Permit" flow | M |
| T9.1.4 | Support setting primary permit | S |
| T9.1.5 | Persist changes to UserDefaults | S |

**US9.2: As a user, I can customize map preferences.**

| Task | Description | Estimate |
|------|-------------|----------|
| T9.2.1 | Add toggle for floating map visibility | S |
| T9.2.2 | Add picker for map position | S |
| T9.2.3 | Add picker for map style (light/dark/satellite) | S |
| T9.2.4 | Persist preferences to UserDefaults | S |

**US9.3: As a user, I can view app information and get help.**

| Task | Description | Estimate |
|------|-------------|----------|
| T9.3.1 | Create SettingsView with sections | M |
| T9.3.2 | Show app version and data version | S |
| T9.3.3 | Add Privacy Policy link/view | S |
| T9.3.4 | Add Open Source Licenses view | S |
| T9.3.5 | Add FAQ view | M |
| T9.3.6 | Add "Report Issue" email link | S |
| T9.3.7 | Add "Rate App" App Store link | S |

---

### Epic 10: Error Handling & Edge Cases

**Goal:** Handle errors gracefully with clear user communication.

#### User Stories

**US10.1: As a user, I see helpful messages when something goes wrong.**

| Task | Description | Estimate |
|------|-------------|----------|
| T10.1.1 | Create error state views for common scenarios | M |
| T10.1.2 | Handle "location denied" with settings prompt | M |
| T10.1.3 | Handle "location unavailable" (GPS timeout) | S |
| T10.1.4 | Handle "outside coverage area" | S |
| T10.1.5 | Handle "data loading failed" | S |

**US10.2: As a user, I see loading states while data is being fetched.**

| Task | Description | Estimate |
|------|-------------|----------|
| T10.2.1 | Create loading indicator component | S |
| T10.2.2 | Show loading during initial location acquisition | S |
| T10.2.3 | Show loading during zone lookup | S |
| T10.2.4 | Show loading during refresh | S |

---

### Epic 11: Accessibility

**Goal:** Ensure app is usable by all users regardless of ability.

#### User Stories

**US11.1: As a VoiceOver user, I can navigate and understand all content.**

| Task | Description | Estimate |
|------|-------------|----------|
| T11.1.1 | Add accessibility labels to all interactive elements | M |
| T11.1.2 | Add accessibility hints where helpful | S |
| T11.1.3 | Ensure logical reading order | M |
| T11.1.4 | Test full flow with VoiceOver enabled | M |

**US11.2: As a user with vision impairments, I can read all text.**

| Task | Description | Estimate |
|------|-------------|----------|
| T11.2.1 | Implement Dynamic Type support throughout | M |
| T11.2.2 | Test with largest accessibility text sizes | S |
| T11.2.3 | Ensure High Contrast mode compatibility | S |
| T11.2.4 | Verify color-blind friendly status indicators | S |

**US11.3: As a user who prefers reduced motion, animations are minimized.**

| Task | Description | Estimate |
|------|-------------|----------|
| T11.3.1 | Check @Environment(\.accessibilityReduceMotion) | S |
| T11.3.2 | Disable/reduce animations when preference is set | S |

---

### Epic 12: Testing & Quality

**Goal:** Ensure code quality through automated testing.

#### User Stories

**US12.1: As a developer, I have unit tests for business logic.**

| Task | Description | Estimate |
|------|-------------|----------|
| T12.1.1 | Write tests for ZoneLookupEngine | L |
| T12.1.2 | Write tests for RuleInterpreter | L |
| T12.1.3 | Write tests for PermitService | M |
| T12.1.4 | Write tests for GeoJSONParser | M |
| T12.1.5 | Achieve >80% coverage for Core/Services | L |

**US12.2: As a developer, I have UI tests for critical flows.**

| Task | Description | Estimate |
|------|-------------|----------|
| T12.2.1 | Set up UI test target | S |
| T12.2.2 | Write test for onboarding flow | M |
| T12.2.3 | Write test for main result view | M |
| T12.2.4 | Write test for settings flow | M |

> **Note:** Full UI test suite documented in TestPlan.md (placeholder).

---

## Dependencies

### Internal Dependencies

```
┌─────────────────────────────────────────────────────────────┐
│                    Dependency Graph                          │
└─────────────────────────────────────────────────────────────┘

Epic 1 (Foundation) ──► All other Epics

Epic 2 (Data Layer) ──► Epic 4 (Zone Lookup)
                    ──► Epic 5 (Rule Interpreter)

Epic 3 (Location) ──► Epic 4 (Zone Lookup)
                  ──► Epic 6 (Main Result View)
                  ──► Epic 7 (Map)

Epic 4 (Zone Lookup) ──► Epic 5 (Rule Interpreter)
                     ──► Epic 6 (Main Result View)

Epic 5 (Rule Interpreter) ──► Epic 6 (Main Result View)

Epic 6 (Main Result View) ──► Epic 8 (Onboarding) [shares components]

Epic 7 (Map) ──► Epic 6 (integrates as floating widget)

Epic 8 (Onboarding) ──► Epic 6 (navigates to main view)

Epic 9 (Settings) ──► Independent (can parallel after Epic 1)

Epic 10 (Error Handling) ──► Epics 3, 4, 6 (integrated)

Epic 11 (Accessibility) ──► Epics 6, 7, 8, 9 (applied to all views)

Epic 12 (Testing) ──► Epics 2, 3, 4, 5 (tests business logic)
```

### External Dependencies

| Dependency | Version | Purpose | Risk Level |
|------------|---------|---------|------------|
| **Google Maps SDK** | Latest | Map rendering | Low |
| **CoreLocation** | iOS 16+ | Location services | None (system) |
| **SwiftUI** | iOS 16+ | UI framework | None (system) |
| **XCTest** | Latest | Unit testing | None (system) |

### Data Dependencies

| Dependency | Source | Status |
|------------|--------|--------|
| SF Zone Boundaries | Mock data (manual creation) | Required for Sprint 1 |
| Permit Area Definitions | SFMTA reference | Required for Sprint 1 |
| Rule Definitions | Product brief + SFMTA | Required for Sprint 1 |

---

## Risks & Mitigation

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **Zone boundary accuracy** | High | Medium | Use simplified boundaries in V1; log edge cases; iterate based on user feedback |
| **Point-in-polygon performance** | Low | Medium | Implement spatial index (R-tree); optimize for common case |
| **Google Maps SDK cost** | Low | Low | Monitor usage; MapLibre abstraction ready if needed |
| **iOS 16+ limitation** | Low | Low | Target covers ~95% of active iPhones |
| **Mock data staleness** | Medium | Low | Version display in settings; quarterly review plan |

### Process Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **CI/CD not defined** | High | Medium | Define before TestFlight beta (Sprint 4); placeholder in place |
| **Beta tester recruitment** | Medium | Medium | Start outreach in Sprint 3; target 50-100 SF residents |
| **App Store rejection** | Low | High | Follow Apple guidelines; review before submission |
| **Scope creep** | Medium | Medium | Strict MVP scope; defer features to V1.1 |

### Known Technical Debt

| Item | Description | Plan to Address |
|------|-------------|-----------------|
| Conditional permit validity | Flagged but not enforced | Implement in V1.1 if validated as use case |
| Future permit types | UI space reserved, not implemented | Add in V1.1+ based on user demand |
| Backend integration | Mock data only in V1 | Full implementation in V2 |
| Multi-city support | Architecture ready, data SF-only | Expand in V2 |

---

## Test Plan

> **Note:** Detailed test plan is maintained in `TestPlan.md`. This section provides an overview.

### Test Strategy Overview

| Test Type | Scope | Coverage Target | Timing |
|-----------|-------|-----------------|--------|
| **Unit Tests** | Business logic (Services, Engines) | >80% | During development |
| **Integration Tests** | Service interactions | Key flows | Sprint 4 |
| **UI Tests** | Critical user flows | Onboarding, main view | Sprint 4 |
| **Manual QA** | Full app functionality | All features | Each sprint |
| **Accessibility Testing** | VoiceOver, Dynamic Type | All interactive elements | Sprint 4 |
| **Field Testing** | Real-world location accuracy | Multiple SF locations | Beta period |

### Unit Test Coverage Requirements

| Module | Target Coverage | Priority |
|--------|-----------------|----------|
| ZoneLookupEngine | >90% | P0 |
| RuleInterpreter | >90% | P0 |
| GeoJSONParser | >80% | P1 |
| PermitService | >80% | P1 |
| LocationService | >70% | P2 |
| ViewModels | >70% | P2 |

### UI Test Scenarios

| Scenario | Description | Priority |
|----------|-------------|----------|
| Onboarding complete flow | New user from welcome to main view | P0 |
| Permit validation display | Zone shows correct validity status | P0 |
| Map expand/collapse | Floating map expands and returns | P1 |
| Settings permit management | Add/edit/delete permits | P1 |
| Error state display | Location denied shows proper message | P1 |

### Field Testing Plan

| Test | Location Type | Validation |
|------|---------------|------------|
| RPP Zone A | Known Area A address | Confirm zone detected |
| RPP Zone Q | Known Area Q address | Confirm zone detected |
| Zone boundary | Cross-street between zones | Verify boundary handling |
| Metered zone | Downtown SF | Confirm metered detection |
| Outside coverage | Ocean Beach edge | Confirm error message |

---

## Definition of Done

### Per Task

- [ ] Code implemented and compiles without warnings
- [ ] Unit tests written and passing (where applicable)
- [ ] Code reviewed and approved
- [ ] No new linting errors
- [ ] Documentation updated (inline comments for complex logic)

### Per User Story

- [ ] All tasks completed
- [ ] Acceptance criteria verified
- [ ] UI matches design specifications
- [ ] Accessibility requirements met
- [ ] No P0/P1 bugs open

### Per Epic

- [ ] All user stories completed
- [ ] Integration tested with dependent epics
- [ ] Performance benchmarks met
- [ ] Stakeholder demo completed
- [ ] Epic retrospective documented

### Per Milestone

| Milestone | Definition of Done |
|-----------|-------------------|
| **M1: Foundation** | Project builds, mock data loads, location service returns coordinates |
| **M2: Core Flow** | Can enter coordinates and see correct zone/validity on debug screen |
| **M3: Map Integration** | Floating map shows user location, zone boundaries render correctly |
| **M4: Onboarding** | New user flow complete, permits saved, navigates to main view |
| **M5: Settings** | All settings functional, preferences persist across app launches |
| **M6: Beta Ready** | All MVP features working, no P0/P1 bugs, TestFlight build approved |
| **M10: App Store Launch** | App Store listing approved, app downloadable, no launch blockers |

### Release Criteria (MVP)

- [ ] All MVP milestones (M1-M6) completed
- [ ] Crash-free rate >99%
- [ ] No P0 bugs, <3 P1 bugs with workarounds
- [ ] Performance targets met (zone lookup <500ms, launch <1s)
- [ ] Accessibility audit passed
- [ ] Privacy policy published
- [ ] App Store metadata complete (screenshots, description)
- [ ] TestFlight beta period completed (2 weeks, 50+ testers)
- [ ] Beta feedback addressed

---

## Appendix: Estimation Key

| Size | Estimate | Description |
|------|----------|-------------|
| **S** | Small | Few hours, straightforward |
| **M** | Medium | 1-2 days, moderate complexity |
| **L** | Large | 3-5 days, significant complexity |
| **XL** | Extra Large | 1+ week, high complexity (should be broken down) |

---

**Document Owner:** Engineering Team
**Next Review:** Weekly during active development
**Related Documents:** TechnicalArchitecture.md, ProductBrief.md, TestPlan.md, Backend.md
