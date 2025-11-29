# Blockface Data Layer Migration Strategy

## Executive Summary

**Decision:** Yes, migrate to blockface-based data layer using a **hybrid approach** with **phased rollout** and comprehensive **fallback mechanisms**.

**Timeline:** 6-8 weeks for full migration (across S23-S26)

**Risk Level:** Medium (mitigated through phasing and testing)

---

## Current State vs. Proposed State

### Current Architecture (Zone-Based)

```
User Location → Point-in-Polygon Lookup → RPP Zone → Zone Rules → Display
```

- **24 RPP zones** with ~3,600 polygon boundaries
- Zone-wide rules (entire Area Q has same rules)
- Fast lookup (spatial index on 24 zones)
- Limited granularity (cannot represent street-by-street variations)
- Missing data: meters, street cleaning, time limits, loading zones

### Proposed Architecture (Blockface-Based)

```
User Location → Nearest Blockface Lookup → Street Segment → Blockface Rules → Display
                      ↓ (fallback)
                  Zone Lookup → RPP Zone → Zone Rules
```

- **18,355 blockface segments** with detailed parking regulations
- Street-by-street granularity (both sides of street can differ)
- More complex lookup (nearest-neighbor with spatial constraints)
- Rich data: permits, meters, time limits, street cleaning, restrictions
- Official authoritative source (DataSF parking regulations dataset)

---

## Benefits of Migration

### 1. **Accuracy & Granularity**
- Street-level precision vs. zone-wide approximations
- Capture side-of-street differences (east vs. west side rules differ)
- Accurate "Park Until" times based on actual time limits
- Exact enforcement hours per blockface

### 2. **Feature Completeness**
- **Metered parking** with rates and time limits
- **Street cleaning** schedules with exact days/times
- **Time-limited zones** (2-hour, 4-hour parking)
- **Loading zones** and commercial restrictions
- **Tow-away zones** with active hours

### 3. **User Experience**
- "You can park here for 2 hours" vs. "You're in Area Q"
- Show nearest alternative if current spot invalid
- Indicate which side of street to park on
- Display cost for metered spots
- Warn about upcoming street cleaning

### 4. **Data Authority**
- DataSF is official source (maintained by SFMTA)
- Updates reflect actual on-street signage
- Legal accuracy for enforcement information
- Comprehensive city-wide coverage

### 5. **Scalability**
- Easy to add new restriction types as data becomes available
- Can extend to non-RPP areas (metered, time-limited, unregulated)
- Foundation for multi-city expansion
- Supports future features (parking history, session management)

---

## Risks & Mitigation Strategies

### Risk 1: Performance Degradation

**Concern:** 18K blockfaces vs. 24 zones = 750x more data to query

**Impact:** Slower lookups, UI lag, poor user experience

**Mitigation:**
- ✅ **Spatial indexing** (R-tree with bounding boxes) - implemented in S20.1-20.3
- ✅ **Caching** (cache nearby blockfaces based on location)
- ✅ **Lazy loading** (load metadata first, geometry on demand)
- **Distance culling** (only query blockfaces within 100m radius)
- **Progressive disclosure** (show primary blockface first, others on tap)
- **Performance budget** (< 100ms for 95th percentile lookups)
- **Monitoring** (track lookup times in production)

**Target:** Lookup time < 100ms (same as current zone lookup)

### Risk 2: Lookup Ambiguity

**Concern:** GPS accuracy may not determine correct blockface (5-15m accuracy, streets 10-20m apart)

**Impact:** Wrong side of street, intersection confusion, user frustration

**Mitigation:**
- **Confidence scoring** (high/medium/low based on GPS accuracy and distance)
- **Show alternatives** ("Other side of street: different rules")
- **User confirmation** ("Are you parked on Valencia St?" with map)
- **Smart defaults** (most restrictive blockface when ambiguous)
- **Visual feedback** (highlight selected blockface on map)
- **Manual override** (tap to select specific blockface)
- **Hybrid fallback** (use zone if blockface lookup uncertain)

**Target:** > 90% lookup confidence in urban areas

### Risk 3: Data Quality Issues

**Concern:** Blockface data may have gaps, errors, or outdated information

**Impact:** Incorrect parking rules, user gets ticketed, trust loss

**Mitigation:**
- **Data validation** (automated checks in pipeline: geometry, required fields, rule consistency)
- **Manual QA** (spot-check random blockfaces against street signs)
- **User feedback** (easy "report issue" button with location capture)
- **Version tracking** (know when data was last updated)
- **Fallback to zones** (if blockface data missing/invalid, use zone rules)
- **Confidence indicators** ("Last verified: 2 weeks ago")
- **Incremental updates** (daily pipeline runs to catch changes)

**Target:** < 2% error rate (measured against ground truth)

### Risk 4: User Confusion

**Concern:** Multiple blockfaces nearby, complex rules, unclear which applies

**Impact:** Analysis paralysis, app abandonment, poor reviews

**Mitigation:**
- **Clear primary choice** (bold "YOU ARE HERE" with single recommendation)
- **Progressive disclosure** (expand for details, alternatives)
- **Visual map** (highlight blockface on map with color coding)
- **Simple language** ("Park here until 6 PM" not "Blockface 12345 enforcement ends 18:00")
- **Contextual help** ("Why this blockface?" explanation)
- **Onboarding** (tutorial for blockface-based lookups)
- **A/B testing** (validate UX with real users before full rollout)

**Target:** < 5% support requests related to confusion

### Risk 5: Development Complexity

**Concern:** Significant refactoring of core lookup logic, data models, UI

**Impact:** Long timeline, bugs, technical debt, delayed features

**Mitigation:**
- **Phased approach** (incremental changes, not big-bang rewrite)
- **Feature flags** (toggle blockface vs zone lookup in production)
- **Comprehensive testing** (unit, integration, UI tests for new logic)
- **Code reviews** (peer review of critical lookup algorithms)
- **Beta testing** (TestFlight with limited users before public release)
- **Rollback plan** (can revert to zone-based lookup if issues arise)
- **Documentation** (architectural decisions, lookup algorithms)

**Target:** Zero regressions in existing functionality

### Risk 6: Rollback Difficulty

**Concern:** Hard to revert after migration if major issues discovered

**Impact:** Stuck with broken system, emergency hotfix pressure

**Mitigation:**
- **Feature flag architecture** (can disable blockface lookup remotely)
- **Keep zone data** (maintain zones as fallback layer permanently)
- **Dual lookup** (run both lookups in parallel during transition, compare)
- **Gradual rollout** (5% → 25% → 50% → 100% of users)
- **Monitoring** (crash reports, error rates, performance metrics)
- **Kill switch** (instant revert to zone lookup if critical bug)
- **Version pinning** (can roll back app version if needed)

**Target:** Rollback possible within 1 hour if critical issue

---

## Phased Migration Plan

### Phase 0: Foundation (Current - S17.27-32)
**Status:** ✅ Complete
- Blockface data loading
- PoC visualization with offset polygons
- Developer settings for tuning
- Performance baseline established

### Phase 1: Lookup Prototype (S23 - Week 1-2)
**Goal:** Prove blockface lookup is feasible
- Implement nearest-neighbor spatial lookup
- Test accuracy with various GPS scenarios
- Benchmark performance with full dataset
- Design UI for blockface-based results
- **Decision point:** Proceed or abort migration

### Phase 2: Hybrid Implementation (S23 - Week 2-3)
**Goal:** Both systems running side-by-side
- Implement blockface lookup alongside zone lookup
- Feature flag to switch between modes
- Dual lookup mode (compare results, log discrepancies)
- Fallback logic (zones when blockface fails)
- **Decision point:** Blockface accuracy sufficient?

### Phase 3: Rich Data Integration (S24-25 - Week 4-5)
**Goal:** Add meters and street cleaning
- Integrate street cleaning schedules (S24)
- Add meter data with costs (S25)
- Update "Park Until" to use blockface limits
- Enhanced UI for metered/cleaning info
- **Decision point:** Data quality acceptable?

### Phase 4: Beta Testing (S26 - Week 6)
**Goal:** Validate with real users
- TestFlight release with blockface lookup enabled
- 50+ SF residents test in real parking scenarios
- Collect feedback on accuracy, UX, performance
- Compare ticket rates (blockface users vs. zone users)
- **Decision point:** User satisfaction > 80%?

### Phase 5: Gradual Rollout (S26 - Week 7-8)
**Goal:** Production deployment with monitoring
- 5% of users (blockface lookup enabled)
- Monitor crash rates, error logs, performance
- 25% rollout if metrics healthy
- 50% rollout if no issues
- 100% rollout with zone fallback always available
- **Decision point:** Continue, pause, or rollback?

### Phase 6: Optimization & Refinement (Post-Launch)
**Goal:** Improve based on production data
- Analyze lookup performance in real-world conditions
- Tune spatial index and caching strategies
- Refine UI based on user behavior analytics
- Address edge cases discovered in production
- Maintain zones as permanent fallback layer

---

## Hybrid Approach: Best of Both Worlds

**Key Insight:** Don't replace zones entirely—use blockfaces for detail, zones for context

### Lookup Flow
```
1. User location acquired (GPS or tap)
2. Run blockface lookup (nearest within 50m)
   ├─ High confidence (< 10m, good GPS) → Use blockface
   ├─ Medium confidence (10-25m) → Show blockface + zone confirmation
   └─ Low confidence (> 25m, poor GPS) → Use zone lookup
3. Always show zone context ("Area Q - Valencia St")
4. Display blockface rules if available, zone rules as fallback
```

### Map Visualization
- **Zoomed out (city-wide):** Show zone polygons (performance, overview)
- **Zoomed in (neighborhood):** Show blockface lanes (detail, accuracy)
- **User location:** Highlight both current zone AND current blockface
- **Toggle layers:** User can show/hide zones, blockfaces, meters independently

### Data Storage
- **Zones:** Always loaded (small dataset, fast queries)
- **Blockfaces:** Lazy-loaded by geographic region (viewport-based)
- **Meters:** Loaded on-demand when "Metered Parking" layer enabled
- **Cache:** Keep recently accessed blockfaces in memory (LRU cache)

### Benefits
- ✅ Fast fallback when blockface lookup uncertain
- ✅ Zone-based overview for navigation
- ✅ Blockface-level accuracy when needed
- ✅ Graceful degradation if blockface data unavailable
- ✅ User can verify "Am I in the right zone?" before trusting blockface

---

## Success Metrics

### Performance
- ✅ Blockface lookup < 100ms (95th percentile)
- ✅ App startup < 2 seconds with full dataset
- ✅ Memory usage < 150MB typical usage
- ✅ No UI jank during lookup or map rendering

### Accuracy
- ✅ > 90% lookup confidence in urban areas
- ✅ < 2% error rate vs. ground truth (street signs)
- ✅ > 95% agreement between blockface and zone when both available
- ✅ < 5% user-reported inaccuracies

### User Experience
- ✅ > 80% user satisfaction (beta testing survey)
- ✅ < 5% support requests related to lookup confusion
- ✅ > 70% users prefer blockface over zone (A/B test)
- ✅ Average session length increases (more engagement)

### Reliability
- ✅ < 0.1% crash rate related to blockface lookup
- ✅ < 1% fallback to zone lookup (indicates high blockface coverage)
- ✅ Zero parking tickets attributed to app error (self-reported)
- ✅ Rollback possible within 1 hour if critical issue

---

## Database Architecture Recommendation

### Central Database: Yes, with Pipeline

**Recommended Stack:**
- **Database:** PostgreSQL + PostGIS (spatial queries)
- **Pipeline:** Python scripts (DataSF fetchers, transformers, validators)
- **Scheduling:** GitHub Actions or cron (daily runs)
- **Storage:** S3 or similar (GeoJSON exports for app bundling)
- **API (future):** FastAPI with spatial endpoints (S11 - post-Alpha)

**Pipeline Flow:**
```
DataSF APIs → Fetch → Transform → Validate → Database → Export GeoJSON → Bundle in iOS App
                                                      ↓
                                              (Future: REST API)
```

**Benefits:**
- Single source of truth for parking data
- Automated daily updates from DataSF
- Version history and rollback capability
- Can serve both bundled and API-based clients
- Foundation for backend services (S11)

**Storage Strategy:**
- **Alpha:** Bundle GeoJSON in app (current approach, S12)
- **Beta:** Hybrid (bundled baseline + API for updates, S11)
- **Production:** API-first with offline fallback cache

---

## Migration Blockers & Dependencies

### Blockers
1. **S23 not started** - Lookup algorithm must prove feasibility
2. **Performance unknown** - Need benchmarks with full dataset
3. **UI design incomplete** - Blockface result cards need design approval
4. **Data quality unvalidated** - Need QA pass on blockface dataset

### Dependencies
- ✅ S17.27-32: Blockface PoC (complete)
- ⏳ S23: Parking Rules & Location Lookups (blocks migration decision)
- ⏳ S20.10-12: Performance benchmarks (validates feasibility)
- ⏳ S24-25: Rich data integration (required for feature parity)
- ⏳ S26: Migration epic (orchestrates rollout)

### Critical Path
```
S23 (Lookup Prototype) → Decision: Go/No-Go
   ↓ (if Go)
S23 (Hybrid Implementation) → S24 (Street Cleaning) → S25 (Meters) → S26 (Migration) → Production
   ↓ (if No-Go)
Continue with zone-based system, use blockfaces for visualization only
```

---

## Recommendation

**Proceed with migration using hybrid approach:**

1. **Complete S23** to validate lookup feasibility (2 weeks)
2. **Decision point** after S23: Evaluate accuracy, performance, UX
3. **If positive:** Continue to S24-S25 for rich data (3 weeks)
4. **If negative:** Abort migration, use blockfaces for map visualization only
5. **S26 orchestrates** phased rollout with comprehensive monitoring (3 weeks)
6. **Maintain zones** as permanent fallback and overview layer
7. **Gradual rollout** with kill switch for instant revert

**Total timeline:** 8 weeks from S23 start to full production rollout

**Risk:** Medium (many unknowns, but mitigated through phasing)

**Reward:** High (dramatically better UX, feature completeness, competitive advantage)

---

**Last Updated:** November 2025
**Related Docs:** ImplementationChecklist.md (S23-S26), blockface_offset_strategy.md, DEVELOPER_OVERLAY_TOOLS.md
