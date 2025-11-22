# Test Plan: SF Parking Zone Finder

**Version:** 1.0
**Last Updated:** November 2025
**Status:** Placeholder (To be expanded during development)
**Authors:** Engineering Team

---

## Table of Contents

1. [Overview](#overview)
2. [Test Strategy](#test-strategy)
3. [Unit Tests](#unit-tests)
4. [Integration Tests](#integration-tests)
5. [UI Tests](#ui-tests)
6. [Backend Tests](#backend-tests)
7. [Field Testing](#field-testing)
8. [Accessibility Testing](#accessibility-testing)
9. [Performance Testing](#performance-testing)
10. [Test Environments](#test-environments)
11. [Test Data](#test-data)
12. [Defect Management](#defect-management)

---

## Overview

This document outlines the testing strategy for SF Parking Zone Finder. It will be expanded as features are developed.

### Testing Objectives

1. **Correctness:** Ensure zone lookup and permit validation return accurate results
2. **Reliability:** Verify app handles edge cases and errors gracefully
3. **Performance:** Confirm app meets performance targets
4. **Accessibility:** Validate app is usable by all users
5. **User Experience:** Ensure flows are intuitive and bug-free

### Quality Gates

| Phase | Requirements |
|-------|--------------|
| **PR Merge** | All unit tests pass, code review approved |
| **Sprint Complete** | Integration tests pass, no P0/P1 bugs |
| **Beta Release** | All tests pass, QA sign-off, accessibility audit |
| **App Store Release** | Beta feedback addressed, crash-free rate >99% |

---

## Test Strategy

### Test Pyramid

```
                    ┌─────────────┐
                    │   Manual    │  ← Field testing, exploratory
                    │     QA      │
                    ├─────────────┤
                    │     E2E     │  ← Critical user flows
                    │   UI Tests  │
                ┌───┴─────────────┴───┐
                │    Integration      │  ← Service interactions
                │       Tests         │
            ┌───┴─────────────────────┴───┐
            │         Unit Tests          │  ← Business logic
            │      (80%+ coverage)        │
            └─────────────────────────────┘
```

### Test Types by Phase

| Phase | Unit | Integration | UI | Manual | Field |
|-------|------|-------------|-----|--------|-------|
| **MVP Sprint 1-2** | Yes | No | No | Limited | No |
| **MVP Sprint 3-4** | Yes | Yes | Yes | Full | No |
| **Beta** | Yes | Yes | Yes | Full | Yes |
| **V1.1** | Yes | Yes | Yes | Full | Yes |
| **V2.0 (Backend)** | Yes | Yes | Yes | Full | Yes |

---

## Unit Tests

### Coverage Targets

| Module | Target | Priority |
|--------|--------|----------|
| `ZoneLookupEngine` | >90% | P0 |
| `RuleInterpreter` | >90% | P0 |
| `GeoJSONParser` | >80% | P1 |
| `PermitService` | >80% | P1 |
| `LocationService` | >70% | P2 |
| `ViewModels` | >70% | P2 |

### Test Cases (To Be Expanded)

#### ZoneLookupEngine

| Test ID | Description | Status |
|---------|-------------|--------|
| ZLE-001 | Point clearly inside single zone returns correct zone | Pending |
| ZLE-002 | Point outside all zones returns outsideCoverage | Pending |
| ZLE-003 | Point near boundary returns multiple zones | Pending |
| ZLE-004 | Point exactly on boundary defaults to most restrictive | Pending |
| ZLE-005 | Performance: 1000 lookups complete in <1 second | Pending |
| ZLE-006 | Empty zone data returns appropriate error | Pending |

#### RuleInterpreter

| Test ID | Description | Status |
|---------|-------------|--------|
| RI-001 | User with matching permit returns valid status | Pending |
| RI-002 | User with non-matching permit returns invalid status | Pending |
| RI-003 | User with multiple permits, one matching, returns valid | Pending |
| RI-004 | User with multiple matching permits returns multipleApply | Pending |
| RI-005 | Zone not requiring permit returns noPermitRequired | Pending |
| RI-006 | Rule summary generation produces readable output | Pending |
| RI-007 | Conditional rules are flagged but not enforced | Pending |

#### GeoJSONParser

| Test ID | Description | Status |
|---------|-------------|--------|
| GJP-001 | Valid JSON parses successfully | Pending |
| GJP-002 | Invalid JSON throws appropriate error | Pending |
| GJP-003 | Missing required fields rejected | Pending |
| GJP-004 | Malformed coordinates rejected | Pending |
| GJP-005 | Large file (1000+ zones) parses within timeout | Pending |

#### PermitService

| Test ID | Description | Status |
|---------|-------------|--------|
| PS-001 | Save permit persists to UserDefaults | Pending |
| PS-002 | Load permits retrieves saved permits | Pending |
| PS-003 | Delete permit removes from storage | Pending |
| PS-004 | Primary permit designation works | Pending |
| PS-005 | Multiple permits for same area handled | Pending |

---

## Integration Tests

### Service Integration

| Test ID | Description | Status |
|---------|-------------|--------|
| INT-001 | Location → ZoneLookup → RuleInterpreter flow | Pending |
| INT-002 | Data loading → Caching → ZoneLookup flow | Pending |
| INT-003 | Onboarding → Permit save → Main view flow | Pending |
| INT-004 | Settings change → Preference persistence flow | Pending |

### API Integration (V2.0)

| Test ID | Description | Status |
|---------|-------------|--------|
| API-001 | Successful zone fetch from backend | Pending |
| API-002 | Offline fallback to cached data | Pending |
| API-003 | Version mismatch triggers data refresh | Pending |
| API-004 | Network timeout handled gracefully | Pending |
| API-005 | Rate limiting error displayed to user | Pending |

---

## UI Tests

### Critical User Flows

| Test ID | Flow | Steps | Status |
|---------|------|-------|--------|
| UI-001 | Onboarding Complete | Launch → Welcome → Location Permission → Permit Setup → Main View | Pending |
| UI-002 | Zone Display | Launch → Location acquired → Zone displayed with validity | Pending |
| UI-003 | Map Expand/Collapse | Tap floating map → Full screen → Back to results | Pending |
| UI-004 | Refresh Location | Pull to refresh → Loading → Updated result | Pending |
| UI-005 | Add Permit | Settings → Manage Permits → Add → Save → Return | Pending |
| UI-006 | Error State | Deny location → Error message → Settings link | Pending |

### UI Component Tests

| Test ID | Component | Validation | Status |
|---------|-----------|------------|--------|
| UIC-001 | ValidityBadge | Correct color and text for each status | Pending |
| UIC-002 | ZoneStatusCard | Zone name displayed prominently | Pending |
| UIC-003 | RulesSummary | Rules formatted as bullet points | Pending |
| UIC-004 | FloatingMapWidget | Correct size and position | Pending |
| UIC-005 | OverlappingZonesView | All zones displayed when applicable | Pending |

---

## Backend Tests

> **Note:** Backend tests apply to V2.0 when backend is implemented.

### API Endpoint Tests

| Test ID | Endpoint | Test Type | Status |
|---------|----------|-----------|--------|
| BE-001 | GET /cities | Response structure validation | Pending |
| BE-002 | GET /cities/{code}/zones | Pagination handling | Pending |
| BE-003 | POST /lookup | Correct zone returned | Pending |
| BE-004 | POST /lookup | Outside coverage error | Pending |
| BE-005 | GET /zones/{id} | Zone details returned | Pending |
| BE-006 | GET /health | Health check response | Pending |

### Database Tests

| Test ID | Test | Status |
|---------|------|--------|
| DB-001 | Spatial index performance (10k zones) | Pending |
| DB-002 | Point-in-polygon query accuracy | Pending |
| DB-003 | City detection query | Pending |
| DB-004 | Data migration scripts | Pending |

### Pipeline Tests

| Test ID | Test | Status |
|---------|------|--------|
| PL-001 | DataSF source extraction | Pending |
| PL-002 | Data transformation and normalization | Pending |
| PL-003 | Invalid geometry handling | Pending |
| PL-004 | Version increment on data update | Pending |
| PL-005 | Cache invalidation after pipeline run | Pending |

---

## Field Testing

### Test Locations (San Francisco)

| Location | Zone Type | Test Purpose |
|----------|-----------|--------------|
| 18th & Castro | Area Q (RPP) | Verify residential permit zone |
| Market & Powell | Metered | Verify metered zone detection |
| Divisadero & Haight | Area K / Area N boundary | Test boundary handling |
| Golden Gate Park | No parking / Mixed | Test non-permit zones |
| Financial District | 1-hour metered | Time-limited zone |
| Embarcadero | Tow-away zone | Restricted zone detection |

### Field Test Protocol

1. **Pre-test:** Verify device has GPS enabled, app installed
2. **At location:** Open app, wait for location acquisition
3. **Validation:** Compare displayed zone to physical signage
4. **Record:** Document any discrepancies with photos
5. **Report:** Submit findings via internal tracker

### Field Test Checklist

| Check | Expected | Actual | Pass/Fail |
|-------|----------|--------|-----------|
| Zone name matches signage | | | |
| Permit validity correct | | | |
| Rules summary accurate | | | |
| Map shows correct boundary | | | |
| Address approximately correct | | | |

---

## Accessibility Testing

### VoiceOver Testing

| Test ID | Test | Status |
|---------|------|--------|
| A11Y-001 | All interactive elements have labels | Pending |
| A11Y-002 | Logical reading order on main screen | Pending |
| A11Y-003 | Map expansion announced | Pending |
| A11Y-004 | Form inputs properly labeled | Pending |
| A11Y-005 | Error states announced | Pending |

### Dynamic Type Testing

| Test ID | Test | Status |
|---------|------|--------|
| DT-001 | All text scales with system settings | Pending |
| DT-002 | Layout intact at AX5 (largest) | Pending |
| DT-003 | No text truncation at large sizes | Pending |

### Color & Contrast

| Test ID | Test | Status |
|---------|------|--------|
| CC-001 | Status indicators use shapes + text | Pending |
| CC-002 | High contrast mode compatible | Pending |
| CC-003 | WCAG 2.1 AA contrast ratios met | Pending |

### Motion

| Test ID | Test | Status |
|---------|------|--------|
| MOT-001 | Reduce Motion setting respected | Pending |
| MOT-002 | No essential animations | Pending |

---

## Performance Testing

### Benchmarks

| Metric | Target | Test Method | Status |
|--------|--------|-------------|--------|
| Cold start time | <2 seconds | Xcode Time Profiler | Pending |
| Warm start time | <1 second | Xcode Time Profiler | Pending |
| Zone lookup latency | <500ms | Unit test with timer | Pending |
| Memory footprint | <100 MB | Instruments | Pending |
| Battery impact | <5%/hour | Energy Log | Pending |
| Map render time | <500ms | Manual timing | Pending |

### Load Testing (Backend - V2.0)

| Test | Target | Status |
|------|--------|--------|
| Concurrent requests | 100 req/s sustained | Pending |
| Response time (p99) | <200ms | Pending |
| Database query time | <50ms | Pending |

---

## Test Environments

### iOS Simulators

| Device | iOS Version | Purpose |
|--------|-------------|---------|
| iPhone 15 Pro | iOS 17 | Primary development |
| iPhone 12 | iOS 16 | Minimum supported |
| iPhone SE (3rd gen) | iOS 17 | Small screen testing |
| iPhone 15 Pro Max | iOS 17 | Large screen testing |

### Physical Devices

| Device | iOS Version | Purpose |
|--------|-------------|---------|
| iPhone 13 | Latest | Field testing |
| iPhone 12 Mini | Latest | Small screen field testing |

### Backend Environments (V2.0)

| Environment | Purpose | Data |
|-------------|---------|------|
| Local | Development | Mock data |
| Staging | Integration testing | Test data |
| Production | Live | Real data |

---

## Test Data

### Mock Data Requirements

| Data Type | Volume | Notes |
|-----------|--------|-------|
| Parking zones (SF) | 50-100 zones | Cover major neighborhoods |
| Permit areas | All SF areas (A-Z, Q-Y) | Complete coverage |
| Rules | 3-5 per zone | Varied rule types |
| Edge cases | 10+ scenarios | Boundaries, overlaps |

### Test User Profiles

| Profile | Permits | Use Case |
|---------|---------|----------|
| Single permit holder | Area Q | Typical user |
| Multi-permit holder | Area Q, Area R | Power user |
| No permits | None | Visitor use case |
| Expired permit | Area Q (expired) | Error handling |

---

## Defect Management

### Severity Levels

| Level | Description | Response Time |
|-------|-------------|---------------|
| **P0** | App crash, data loss, security issue | Immediate |
| **P1** | Major feature broken, no workaround | Same day |
| **P2** | Feature impaired, workaround exists | Within sprint |
| **P3** | Minor issue, cosmetic | Backlog |

### Bug Report Template

```
**Title:** [Brief description]

**Severity:** P0 / P1 / P2 / P3

**Environment:**
- Device:
- iOS Version:
- App Version:
- Build:

**Steps to Reproduce:**
1.
2.
3.

**Expected Result:**

**Actual Result:**

**Screenshots/Logs:**

**Additional Notes:**
```

### Test Coverage Tracking

Coverage reports generated on each PR via CI pipeline (to be configured).

---

## Appendix: Test Schedule Template

| Sprint | Unit Tests | Integration | UI Tests | Manual QA | Field |
|--------|------------|-------------|----------|-----------|-------|
| Sprint 1 | ZLE, GJP | - | - | Smoke | - |
| Sprint 2 | RI, PS | INT-001 | - | Feature | - |
| Sprint 3 | ViewModels | INT-002, 003 | UI-001, 002 | Full | - |
| Sprint 4 | All | All | All | Full | Initial |
| Beta | Maintain | Maintain | Maintain | Regression | Full |

---

**Document Owner:** QA / Engineering Team
**Next Review:** Each sprint planning
**Related Documents:** EngineeringProjectPlan.md, TechnicalArchitecture.md
