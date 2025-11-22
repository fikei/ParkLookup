# Product Brief: SF Parking Zone Finder

**Version:** 1.0  
**Last Updated:** November 2025  
**Platform:** iOS (MVP), with future expansion to web and Android  
**Target City:** San Francisco (MVP), designed for multi-city expansion

---

## Overview

SF Parking Zone Finder is a location-based mobile application that helps users instantly understand parking regulations at their current location in San Francisco. The app answers the fundamental question: "Can I park here with my permit?" by displaying real-time parking zone information, permit validity, and applicable rules.

The MVP focuses on delivering a simple, immediate answer through a **full-screen textual result view** that shows parking zone status and permit validity, complemented by a **minimized floating map** for spatial context. Users can expand the map when needed, but the primary interface prioritizes clear, readable information over visual maps.

---

## Primary User

**San Francisco resident with a residential parking permit (RPP)** who:
- Drives regularly within SF
- Holds one or more residential parking permits (Areas A-Z, Q, R, S, T, U, V, W, X, Y)
- Needs quick validation of parking legality in unfamiliar neighborhoods
- Wants to avoid parking tickets due to zone confusion
- Values speed and clarity over complex interfaces

**Secondary users:**
- Visitors with temporary permits
- Commercial vehicle operators
- Residents without permits who need to understand time limits and meter locations
- Out-of-neighborhood residents exploring different SF areas

---

## The Mandatory Primary View

### Full-Screen Result Display

The app's **main screen is a full-screen textual view** that displays:

1. **Current Parking Zone**
   - Example: "Area Q," "Area R," "Permit Only Zone," "2-Hour Metered," etc.
   - Large, prominent display at the top of the screen
   - Uses official SF zone nomenclature

2. **Permit Validity Status**
   - Clear YES/NO indicator: "Your Area Q permit is VALID here" or "Your Area R permit is NOT VALID here"
   - Color-coded: green for valid, red for invalid, yellow for conditional
   - Handles multi-permit scenarios (user may have multiple permits)

3. **Rules Summary**
   - Short, human-readable summary of parking rules
   - Example: "2-hour limit for non-permit holders, 8 AM - 6 PM Mon-Sat"
   - Handles multiple rule scenarios:
     - Street cleaning schedules
     - Meter hours and rates
     - Time-limited parking
     - Special event restrictions
     - Tow-away zones

4. **Minimized Floating Map**
   - Small map widget (approximately 120x120 points) anchored above the result content
   - Shows user location dot and current zone boundary
   - Semi-transparent or with rounded corners to maintain visual hierarchy
   - **Tap or drag** to expand into full-screen map mode
   - Does not interfere with reading the textual result

### Critical Design Principle

**The textual result is always the source of truth.** The map is supplementary visual context, not the primary interface. This ensures:
- Instant comprehension without map interpretation
- Accessibility for users with visual impairments
- Faster decision-making (read text vs. decode map colors)
- Clear legal status without ambiguity
- Works well in bright sunlight (text more readable than maps)
- Reduces cognitive load for quick parking decisions

---

## Onboarding Flow

### First Launch Experience

**Step 1: Welcome Screen**
- App name and tagline: "Know your parking rights instantly"
- Brief explanation: "SF Parking Zone Finder shows you if your permit is valid at your current location"
- Simple illustration showing the main result screen
- "Get Started" button

**Step 2: Location Permission**
- Request "While Using App" location permission
- Clear explanation: "We need your location to show parking zones near you"
- Privacy note: "Your location is never stored or transmitted"
- Handle denial gracefully with option to manually search addresses (future feature)

**Step 3: Permit Collection**
- Question: "Do you have any San Francisco residential parking permits?"
- Options: "Yes" or "Skip for now"
- If Yes:
  - Multi-select interface showing all RPP areas (A-Z, Q, R, S, T, U, V, W, X, Y)
  - Visual permit cards with area identifiers and neighborhood hints
  - Allow multiple permit selection (users can have permits for multiple areas)
  - "Add Another Permit" button
  - Save to local device storage

**Step 4: Tutorial Overlay (Optional, Dismissible)**
- Brief 2-3 screen tutorial showing:
  - How to read the main result screen
  - How to expand the floating map
  - How to refresh location
  - How to manage permits in settings
- "Got it" or "Skip Tutorial" option
- Never shown again once dismissed

### Returning Users
- Skip directly to main screen
- Option to edit permits in settings at any time
- Re-request location permission if previously denied

---

## Main Screen Functionality

### Primary Interface Elements

**Top Section: Zone Status Card**
- **Zone Name:** Large, bold text (e.g., "Area Q" or "2-Hour Metered Zone")
- **Validity Badge:** Colored indicator with text
  - Green: "YOUR PERMIT IS VALID HERE"
  - Red: "YOUR PERMIT IS NOT VALID HERE"
  - Yellow: "CONDITIONAL - SEE RULES BELOW"
  - Gray: "NO PERMIT REQUIRED" or "PUBLIC METERED PARKING"
  - Blue: "MULTIPLE PERMITS APPLY" (when user has more than one valid permit)

**Middle Section: Rules Summary**
- 2-4 line summary of key parking rules
- Bullet points for clarity:
  - "Residential Permit Area Q only"
  - "2-hour limit for non-permit holders"
  - "Enforced Mon-Sat, 8 AM - 6 PM"
  - "No parking during street cleaning: Wed 8-10 AM"
- Expandable "View Full Rules" button for detailed ordinances

**Bottom Section: Additional Info**
- Last updated timestamp (e.g., "Updated just now")
- "Refresh Location" button (manual trigger)
- Current address display (reverse geocoded)
- "Report Issue" link for incorrect zone data

### Floating Map Widget

**Default State (Minimized):**
- Size: ~120x120 points (small, non-intrusive)
- Position: Floating over top-right of screen (not card), anchored to screen coordinates
- Zoom level: 2x closer than standard street-level for tight focus on immediate area
- Content:
  - User's blue location dot with accuracy circle
  - Clean map view without zone label overlay (zone shown in main card)
  - Expand hint icon (arrows) in corner
- Interaction:
  - Single tap: Expands to full-screen map
  - Long press (optional): Allows repositioning of widget
  - Maintains aspect ratio and readability
- Visual design:
  - Rounded corners (12pt radius)
  - Subtle drop shadow
  - Semi-transparent background when over light content

**Expanded State (Full-Screen Map):**
- Triggered by tap on floating map
- Full-screen map interface showing:
  - **All parking zone boundaries** as color-coded polygons
  - User location dot with heading indicator
  - Zone labels directly on map polygons (e.g., "Q", "R", "A")
  - Interactive legend (tap to toggle zone types)
  - "Done" button (prominent, top-right, always visible)
  - Current zone highlighted with thicker border and fill color
- **Zone Boundary Display:**
  - RPP zones shown with semi-transparent fill and distinct border
  - Current zone: Bold accent color fill (20% opacity) + thick border
  - Adjacent zones: Lighter differentiated colors
  - Zone letters displayed centered on polygon
- Map provider: **Apple MapKit** (default) OR **Google Maps SDK** (optional)
- Pan and zoom enabled with standard gestures
- Tapping a zone polygon shows mini info card with:
  - Zone name
  - Basic rules (1-2 lines)
  - "See Details" button (returns to result view with that zone)
- Pinch gesture or "Done" button returns to full-screen result view

### Interaction Flow
[User opens app]
↓
[Location acquired automatically]
↓
[Full-screen result displayed with floating map]
↓
[User reads zone name, validity badge, rules summary]
↓
[Decision made: Can I park here? YES/NO]
↓
[Optional: Tap floating map to see spatial context]
↓
[Full-screen map opens]
↓
[User explores nearby zones visually]
↓
[Tap zone to see its rules]
↓
[Tap "Back to Results" or swipe down]
↓
[Return to full-screen result view]
### Settings Screen

Accessible via gear icon in navigation bar:
- **My Permits:** 
  - Add, edit, or remove residential permits
  - Set primary permit (used first in validation)
  - Add expiration dates (optional reminders)
- **Notification Preferences:**
  - Street cleaning reminders (future feature)
  - Zone change alerts (future feature)
- **Map Preferences:**
  - Choose map style (if MapLibre: light, dark, satellite)
  - Set floating map position (top-left, top-right, bottom-right)
  - Toggle floating map visibility (some users may prefer text-only)
- **About:**
  - App version and build number
  - Data version (mock data v1.0 in MVP)
  - Privacy policy link
  - Terms of service
  - Open source licenses
- **Help & Feedback:**
  - FAQ section
  - Report incorrect zone data
  - Contact support email
  - Rate app on App Store

---

## V1 Scope (MVP)

### In Scope

**Core Features:**
1. Location-based zone detection using device GPS
2. Full-screen parking zone status display with clear permit validity
3. Permit validation against user's stored permits
4. Minimized floating map with expansion capability
5. Onboarding to capture user permit information
6. Manual location refresh button
7. Mock data service for San Francisco zones (embedded JSON)
8. Basic error handling (no GPS, no data coverage, location denied)
9. Settings screen for permit management
10. Reverse geocoding to show current address

**Data Coverage:**
- San Francisco Residential Parking Permit areas (A-Z, Q, R, S, T, U, V, W, X, Y)
- Major metered parking zones in downtown and commercial districts
- Common time-limited parking zones
- No parking zones (red zones, tow-away zones)
- Static mock data (no real-time updates)

**Platforms:**
- iOS 16.0+ (iPhone only)
- iPhone 12 and newer optimized (works on older devices)

**Map Provider Options:**
- Google Maps SDK for iOS OR
- MapLibre with OpenStreetMap tiles
- Abstracted behind protocol for easy switching

### Out of Scope (V1)

**Features:**
- Real-time parking availability (space counting)
- Payment integration for metered parking
- Historical parking data or analytics
- Multi-city support (data included for SF only)
- Apple Watch companion app
- Push notifications or reminders
- Street cleaning calendar integration with reminders
- Parking timer with expiration alerts
- Social features (sharing locations, crowdsourced data)
- Offline map tile caching (system cache only)
- Route planning or navigation
- Integration with parking payment apps (ParkMobile, PayByPhone)

**Data:**
- Real-time meter occupancy
- Dynamic pricing for demand-based meters
- Private parking lots or garages
- Loading zones and commercial vehicle restrictions
- Disabled parking placard zones

**Platforms:**
- iPad (will work but not optimized)
- Android
- Web application
- CarPlay or Android Auto

---

## Data Sources

### V1 (MVP): Mock Data

**Source:** Embedded JSON file in app bundle  
**Location:** `Resources/sf_parking_zones.json`  
**Format:** GeoJSON-like structure with zone boundaries and rules

**Data includes:**
- Simplified zone boundaries (polygons covering major SF neighborhoods)
- Residential Parking Permit area definitions
- Basic time restrictions and meter hours
- Street cleaning schedules (generalized patterns)
- Zone type classifications

**Limitations:**
- Static data (no real-time updates)
- Simplified boundaries (may not match exact street edges)
- Generalized rules (may miss hyperlocal exceptions)
- No integration with SFMTA live data feeds

**Update mechanism:**
- Manual updates via app store releases
- Version number displayed in settings

### Future: Backend API

**Primary sources:**
- [DataSF Open Data Portal](https://data.sfgov.org/)
  - Parking meters dataset
  - Street parking zones
  - Residential permit areas
- [SFMTA (San Francisco Municipal Transportation Agency)](https://www.sfmta.com/)
  - Official RPP area boundaries
  - Meter pricing and hours
  - Street cleaning schedules
  - Temporary parking restrictions

**See `BACKEND_FUTURE.md` for detailed backend architecture.**

---

## Non-Functional Requirements

### Performance
- **Location acquisition:** < 2 seconds on average (device-dependent)
- **Zone lookup:** < 500ms from location to result display
- **Map rendering:** Smooth 60fps on iPhone 12 and newer
- **App launch:** < 1 second to main screen (returning users, warm start)
- **Memory footprint:** < 100 MB typical usage

### Reliability
- Graceful degradation when GPS accuracy is poor (show accuracy indicator)
- Offline capability: last known location cached for 5 minutes
- Error states clearly communicated with actionable next steps
- Network independence (no network required in V1)

### Accessibility
- **VoiceOver support:** All interactive elements properly labeled
- **Dynamic Type:** Text scales with system settings (respects user's font size)
- **High contrast mode:** Compatible with system accessibility settings
- **Color-blind friendly:** Status indicators use shapes + text, not color alone
- **Reduce Motion:** Respects system animation preferences
- **Voice Control:** All actions achievable via voice commands

### Privacy
- **Location data:** Never transmitted to servers in V1 (fully local processing)
- **Permit data:** Stored locally on device only (UserDefaults, not synced)
- **No analytics:** Zero tracking or analytics in V1 (optional opt-in for future versions)
- **Transparency:** Clear privacy policy accessible in onboarding and settings
- **Minimal permissions:** Only "While Using App" location permission requested

### Maintainability
- SwiftUI for all UI components (modern, declarative approach)
- MVVM architecture with clear separation of concerns
- Protocol-oriented design for testability and flexibility
- Mock data service abstraction for easy backend integration
- Comprehensive inline documentation
- Unit test coverage target: >80% for business logic

### Localization (Future)
- V1: English only
- V2+: Spanish (primary secondary language in SF)
- Structure for easy localization (all strings in `Localizable.strings`)

---

## Success Metrics

### Primary Metrics (V1)

**Adoption:**
- **Daily Active Users (DAU):** Target 1,000 within 3 months of launch
- **Retention Rate:** 
  - Day-7: 40%
  - Day-30: 25%
- **Onboarding Completion:** 70% of users complete permit setup

**Engagement:**
- **Time to Answer:** Average time from app open to seeing result < 3 seconds
- **Sessions per Day:** Average 2-3 (users check multiple locations)
- **Map Expansion Rate:** % of sessions where user taps floating map (target: 30-40%)

**Quality:**
- **Error Rate:** < 5% of sessions encounter errors
- **Location Accuracy:** 95% of lookups within correct zone
- **App Store Rating:** Maintain 4.5+ stars with 100+ reviews

### Secondary Metrics

**User Behavior:**
- **Manual Refresh Rate:** Average times user manually refreshes per session
- **Settings Engagement:** % of users who edit permits after onboarding
- **Permit Count:** Average number of permits per active user
- **Time of Day Usage:** Peak usage patterns (likely morning commute, evening parking search)

**Technical Performance:**
- **Crash-Free Rate:** 99.5%+ (less than 0.5% of sessions crash)
- **API Response Time:** (future) 95th percentile < 200ms
- **Battery Impact:** Minimal (measured via Xcode Energy Log)

### User Feedback Goals
- Qualitative feedback themes: "Instant clarity," "Saved me from tickets," "Simple and fast"
- Feature requests tracked and prioritized for V2
- Support tickets < 10 per month (post-launch stabilization period)

---

## Future Features (Post-V1)

### V1.1 - V1.3 (Near-term, 1-3 months post-launch)

**Enhancements:**
- **Real-time location tracking:** Auto-refresh when user moves to new zone
- **Parking timer:** Set reminder when parking in time-limited zone
- **Street cleaning alerts:** Proactive notifications before street cleaning
- **Historical lookups:** "Where did I park yesterday?" feature
- **iPad optimization:** Larger layout with side-by-side result and map
- **Dark mode refinements:** Improved contrast and map styling

**Data improvements:**
- Replace mock data with backend API integration
- Higher-resolution zone boundaries (match street edges)
- Include private parking garage locations (view-only, no payment)

### V2.0 (Medium-term, 6-12 months post-launch)

**Major features:**
- **Multi-city support:** Oakland, Berkeley, San Jose, Palo Alto
- **Web application:** Responsive web app for desktop planning
- **Android app:** Native Android implementation
- **Payment integration:** Pay for metered parking directly in app (ParkMobile API)
- **Permit expiration reminders:** Push notifications before permit expires
- **Favorites:** Save frequently parked locations for quick lookup

**Backend:**
- Full REST API with real-time data (see `BACKEND_FUTURE.md`)
- User accounts for syncing permits and favorites across devices
- Advanced caching for offline resilience

### V3.0+ (Long-term, 12+ months post-launch)

**Advanced features:**
- **Apple Watch app:** Glance at permit validity on wrist, complications
- **CarPlay integration:** Show zones while driving, navigate to legal parking
- **Predictive parking:** ML model suggests nearby legal parking spots based on time/day
- **Community features:** 
  - Report incorrect zones (crowdsourced corrections)
  - Share parking tips with friends
  - Parking availability heatmaps (if data becomes available)
- **Smart city partnerships:** Official data partnerships with SFMTA and other agencies
- **Electric vehicle charging:** Show EV charging station locations and availability
- **Personalized analytics:** "You saved $X in parking tickets this year" dashboard

**Platform expansion:**
- More Bay Area cities (Fremont, Hayward, Richmond, etc.)
- Sacramento, Los Angeles, San Diego (California expansion)
- National expansion: NYC, Boston, Seattle, Portland, Chicago

---

## Multi-City Considerations

### Architecture for Scalability

While V1 focuses on San Francisco, the app is architected from day one to support multiple cities:

**Data structure:**
- Each city has a unique identifier (e.g., `sf`, `oak`, `sj`)
- Zone lookup service includes city parameter (auto-detected from location)
- Backend API routes requests by city (future)

**City-specific rules:**
- Abstract permit validation logic per city
- SF uses alphabetical areas (A-Z) + special areas (Q, R, S, etc.)
- Oakland may use different naming conventions
- Rule interpretation varies by city (meter hours, permit requirements, etc.)

**UI considerations:**
- City selector in settings (future, when multiple cities supported)
- Onboarding asks user's home city to prioritize permit options
- Graceful message when user is outside supported cities: "We don't support parking data for [City Name] yet. Request support in Settings > Help."

**Data management:**
- Separate JSON files per city in V1 mock data
- Backend will have multi-tenanted database with city-scoped queries
- City data versioning (each city may update independently)

### Target Cities for V2

**Tier 1 (High Priority):**
1. **Oakland:** Similar RPP system to SF, high demand from East Bay residents
2. **Berkeley:** Dense residential zones near UC Berkeley campus
3. **San Jose:** Larger geographic area, more metered zones, fewer RPP areas

**Tier 2 (Medium Priority):**
4. **Palo Alto:** High-income area, Stanford University parking challenges
5. **Fremont:** Growing city with evolving parking regulations
6. **Sacramento:** State capital, government worker demand

**Tier 3 (Long-term):**
7. **Los Angeles:** Complex multi-jurisdictional system, huge market potential
8. **San Diego:** Tourist-heavy, beach parking restrictions
9. **National expansion:** NYC, Boston, Seattle, Portland, Chicago

---

## Design Principles

1. **Clarity over cleverness:** Text-first, map-second approach ensures instant comprehension
2. **Speed over features:** Do one thing exceptionally well—answer "Can I park here?"
3. **Privacy by default:** Minimize data collection, respect user privacy always
4. **Build for change:** Abstractions ready for multi-city, multi-platform, backend integration
5. **Accessible to all:** Not just for map experts—readable, clear, inclusive design
6. **Offline-first:** Core functionality works without network (V1 fully offline)
7. **Progressive enhancement:** Map is optional, not required, for primary use case

---

## Open Questions / Decisions Needed

- [ ] **Final map provider decision:** Google Maps or MapLibre? (Recommendation: MapLibre for cost savings and flexibility)
- [ ] **App Store category:** Navigation or Utilities? (Recommendation: Utilities)
- [ ] **Monetization strategy:** 
  - Option A: Free with optional "Pro" features (multi-city, advanced notifications) via $2.99/month subscription
  - Option B: One-time purchase $4.99
  - Option C: Free forever, monetize via city partnerships (preferred for public good)
- [ ] **Launch marketing plan:** 
  - Local SF promotion (flyers in permit-heavy neighborhoods?)
  - Reddit (r/sanfrancisco, r/bayarea)
  - Twitter/X outreach to urbanist influencers
  - Press release to SF Chronicle, SFGate
- [ ] **Data update cadence:** How often refresh mock data before backend? (Recommendation: Quarterly or when SFMTA publishes major changes)
- [ ] **Beta testing plan:** TestFlight with 50-100 SF residents for 2 weeks before launch

---

## Appendix: SF Parking Context

### Residential Parking Permit (RPP) System Overview

San Francisco's RPP program allows residents to park in their designated area without time limits. Key facts:

- **Cost:** $158/year for first vehicle, $169 for additional vehicles (as of 2024)
- **Eligibility:** Must be SF resident with vehicle registered to SF address
- **Area restrictions:** Each permit valid only in designated area (cannot park in different area)
- **Guest permits:** Temporary permits available for visitors
- **Enforcement:** SFMTA parking control officers patrol and issue tickets

**Common confusion:**
- Residents often park in neighboring areas thinking "it's close enough"
- Zone boundaries are not always intuitive (don't follow neighborhood names)
- Some blocks have mixed zoning (part residential, part metered)

**This app solves:** The fundamental confusion about zone boundaries and permit validity in unfamiliar parts of the city.

---

**Document Owner:** Product Team  
**Technical Lead:** Engineering Team  
**Next Review Date:** Post-MVP launch (Q1 2026)