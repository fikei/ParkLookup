# PRD: Data-Model Integration with curb.guide

**Owner:** ParkLookup
**Status:** Draft for review
**Related:** `docs/curb-guide-ticket-window-integration.md` (validated join), `docs/notification-loop-improvement-brief.md` (consumer of this data)
**Branch:** `claude/curb-guide-integration-nif658`

---

## 1. Problem

curb.guide's one unique asset — empirical street-sweeping **ticket-timing** (`enforcement.json`, keyed by CNN × day-of-week) — has no place to live in ParkLookup's current data model. Our `Blockface`/`BlockfaceRegulation` model is keyed by `globalid` (a GUID) and carries **no CNN**, which is the only join key to curb's data. We need to evolve the model to hold this data (and similar future overlays) **without a risky rewrite** and **degrading gracefully** where coverage is missing.

## 2. Goals / Non-goals

**Goals**
- Carry `cnn` on blockfaces/regulations so curb.guide (and any CNN-keyed DataSF) data can join.
- Add an optional `ticketWindow` to street-cleaning regulations.
- Keep 100% backward compatibility: old data files and old app builds must keep working.
- Make the new data strictly optional so partial coverage degrades gracefully.
- Establish a versioned, provenance-bearing data envelope for future overlays.

**Non-goals**
- Re-keying the entire model from `globalid` to `cnn` (evaluated and rejected — see §4).
- Live/server data fetching (separate effort; this PRD keeps the bundled-file model).
- Meter-rate or RPP enforcement-timing (curb data is sweeping-only).

## 3. Current model (from code)

- `Core/Models/Blockface.swift`
  - `Blockface { id (globalid GUID), street, fromStreet, toStreet, side, geometry: LineString, regulations: [BlockfaceRegulation] }` — **no `cnn`**.
  - `BlockfaceRegulation { type: String, permitZone/permitZones, timeLimit, meterRate, enforcementDays, enforcementStart/End, specialConditions }` with **explicit `CodingKeys`** (new fields must be added there) and a non-decoded `id = UUID()`.
  - `isInEffect(at:)` uses **`Calendar.current`** — wrong for a fixed-locale (SF) ruleset; must be `America/Los_Angeles`.
- `Core/Services/BlockfaceLoader.swift` — decodes one ~32MB bundled file into `BlockfaceDataResponse { blockfaces: [Blockface] }`, cached in memory; dataset filename chosen via `DeveloperSettings.blockfaceDataSource` (switchable datasets already exist).
- `backend/pipeline_blockface.py` — `extract_street_sweeping()` reads `weekday/fromhour/tohour` from the DataSF sweep dataset (`yhqp-riqs`) but **drops `cnn`** (the join key).

## 4. Decision: graceful enrichment, not a rewrite

Two options were considered:

**Option A — Graceful enrichment (RECOMMENDED).** Keep `globalid` canonical and the blockface-embedded-regulations shape. Add `cnn` as a join attribute and `ticketWindow` as an optional overlay. Everything new is optional.

**Option B — CNN-canonical rewrite.** Re-key the model to CNN (+ side) to mirror curb.guide's structure and serve precomputed per-purpose JSON files.

**Why A.** curb's only unique asset joins cleanly via `cnn` carried on the existing street-sweeping regulations (the pipeline already spatially binds sweep rules to side-blockfaces — see the integration doc). A full re-key (Option B) would touch every consumer — `BlockfaceLoader`, `ParkingDataAdapter`, overrides keyed by `id` (`BlockfaceOverrideManager`), map overlays, and persisted `ParkingSession`s — for **no functional gain**, and the overlay must be optional regardless because curb covers only ~10,462 CNN blocks. Option B is recorded as a possible future step if/when we adopt live, CNN-keyed, multi-overlay data; it is out of scope here.

## 5. Schema changes

### 5.1 Pipeline output (`backend/pipeline_blockface.py`)
1. Preserve the join key on each blockface:
   ```python
   blockface["cnn"] = str(props.get("cnn")) if props.get("cnn") is not None else None
   ```
2. In `extract_street_sweeping()`, also keep `cnn`, then in a post-join step stamp the window for that reg's weekday:
   ```python
   reg["cnn"] = cnn
   win = enforcement.get(str(cnn), {}).get(str(js_dow(weekday)))   # js_dow: mon=1..sun=0
   if win and win[0] >= MIN_SAMPLES:                               # win = [count, avgMin, loMin, hiMin]
       reg["ticketWindow"] = {"count": win[0], "avgMin": win[1], "loMin": win[2], "hiMin": win[3]}
   ```
   Omit `ticketWindow` entirely when absent/low-sample (graceful).
3. Wrap output with provenance/version (see §6).

### 5.2 Swift model (`Core/Models/Blockface.swift`)
```swift
struct Blockface { ...; let cnn: String?; ... }      // optional

struct TicketWindow: Codable, Hashable {
    let count: Int
    let avgMin: Int     // local-SF minutes past midnight
    let loMin: Int
    let hiMin: Int
}

struct BlockfaceRegulation {
    ...
    let cnn: String?
    let ticketWindow: TicketWindow?
    enum CodingKeys: String, CodingKey {
        case type, permitZone, permitZones, timeLimit, meterRate
        case enforcementDays, enforcementStart, enforcementEnd, specialConditions
        case cnn, ticketWindow          // ADD — required because CodingKeys is explicit
    }
}
```
- Decode with `decodeIfPresent` so older files (no `cnn`/`ticketWindow`) still decode.
- Add convenience: `TicketWindow.range(forSweepOn:)` → `Date` interval in `America/Los_Angeles` for the next sweep occurrence; helper to format "tickets usually land ~12:15 PM".

### 5.3 (Stretch) White zones
curb's `white-zones.json` (SFMTA Digital Curb, unmetered passenger/loading) is a regulation type ParkLookup may not cover. If desired, add a `whiteZone`/`passengerLoading` regulation type sourced the same way. Out of scope for v1; noted for completeness.

## 6. Data envelope & versioning

Extend the bundled file from `{ "blockfaces": [...] }` to:
```json
{ "schemaVersion": 2,
  "meta": { "generated": "...", "ticketWindowSource": "curb.guide enforcement.json (MIT) / SFMTA records #26-5453", "window": "2024-01..2026-06" },
  "blockfaces": [...] }
```
- `BlockfaceDataResponse` decodes `schemaVersion`/`meta` with `decodeIfPresent` (old files → nil, still valid).
- Keep `ticketWindow` baked into the existing blob for v1 (simplest, no new loader). Note a future option to side-load `enforcement.json` as a separate bundled resource to refresh ticket data without regenerating the 32MB blob.

## 7. Graceful-degradation rules
- `cnn` and `ticketWindow` are optional everywhere; absence is normal (≈40% of blockfaces won't have a window).
- UI/notifications must no-op cleanly when `ticketWindow == nil`.
- Always frame as historical/usual ("tickets here usually land ~X"), never a guarantee; posted sign is source of truth.
- Suppress windows below `MIN_SAMPLES` (already enforced at build time; double-check at render).

## 8. Timezone correctness (must-fix, surfaced by this work)
`ticketWindow` minutes are **SF-local**. Any consumer converting `loMin/avgMin/hiMin` → `Date`, and the existing `BlockfaceRegulation.isInEffect(at:)`, must use a fixed `America/Los_Angeles` calendar, not `Calendar.current`. Include the `isInEffect` fix in this work.

## 9. Backward compatibility & migration
- New file + old app: extra keys ignored by `JSONDecoder` → safe.
- Old file + new app: new fields decode to `nil` → safe.
- No change to `globalid` identity → overrides, sessions, map overlays unaffected.
- Ship behind `DeveloperSettings.blockfaceDataSource` (a new dataset entry) so the enriched file can be A/B'd against the current one before becoming default.

## 10. Rollout
1. Pipeline emits `cnn` + `ticketWindow` + envelope; regenerate dataset.
2. Add enriched file as a new `blockfaceDataSource` option; validate coverage.
3. Swift model + timezone fix (no UI yet) — verify decode on both files.
4. Flip default data source once coverage/correctness verified.
5. UI + notification consumers (separate workstream) read `ticketWindow`.

## 11. Risks
- **CodingKeys footgun:** because `BlockfaceRegulation` lists keys explicitly, forgetting to add `cnn`/`ticketWindow` silently drops them — call out in review/tests.
- **Coverage optics:** partial windows can read as "no risk" on uncovered blocks; never imply safety from absence.
- **File size:** `ticketWindow` adds a small per-reg object; verify the 32MB blob doesn't balloon (it shouldn't — only on sweep regs).
- **Timezone regressions:** changing `isInEffect` to fixed-locale could shift existing behavior near midnight/DST — test.

## 12. Success metrics
- % of street-cleaning blockfaces with a `ticketWindow` (target: report actual; expect meaningful majority of swept blocks).
- Zero decode regressions on the legacy file (automated test with both fixtures).
- No change to existing lookup/override/session behavior.

## 13. Open questions
- Bake-in vs side-load for `enforcement.json` (refresh cadence)?
- Adopt white-zones now or defer?
- Do we want the full per-CNN×dow map on the blockface (for any-day queries) or just the window matching each sweep reg's weekday (smaller; v1 default)?
