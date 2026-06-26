# Curb.guide → ParkLookup: ticketWindow Integration (validated feasibility)

**Status:** Join feasibility **confirmed**. Ready to implement. No code changed yet.
**Source repo:** https://github.com/alevizio/curb (MIT) — the open-source code behind https://curb.guide

---

## 1. What curb.guide gives us that DataSF doesn't

curb.guide re-serves the same DataSF feeds ParkLookup already uses, **except** for one derived asset:
`data/enforcement.json` — **when street-sweeping tickets actually land**, per block, per day of week,
computed by matching 800k+ real citations to street segments.

This is empirical *enforcement reality*, layered on top of the *posted schedule* ParkLookup already shows.
It maps directly onto ParkLookup's `streetCleaning` regulation.

## 2. The data (`data/enforcement.json`)

```
{ "<CNN>": { "<jsDow 0=Sun..6=Sat>": [count, avgMinuteOfDay, loMin, hiMin] }, ..., "_meta": {...} }
```
Example: `"6938000": {"1": [17, 736, 722, 753]}` → this block, Mondays: 17 tickets, mean 12:16 PM,
bulk 12:02–12:33 (minutes-of-day, **local SF time**).

`_meta` (authoritative spec from the file itself):
```
generated:  2026-06-25 ; window 2024-01-02 → 2026-06-24 ; min_samples: 5
blocks:     10,462 ; matched_citations: 814,629
source:     SFMTA public-records request #26-5453 (TRC7.2.22 street-cleaning citations, GPS-geocoded)
            joined to yhqp-riqs (segments + schedule)
method:     each citation GPS-matched to nearest CNN segment (<=40m), aggregated by cnn x jsDow
note:       avgMin/loMin/hiMin are local minutes-of-day; dow is JS getDay (0=Sun)
```
- Element 2 is the **mean** (not median); loMin/hiMin are adjusted bounds, not strict percentiles.
- Day-of-week histogram is weekday-heavy (Mon–Fri ~4,200 each, Sat/Sun ~450) — confirms it's sweeping enforcement.
- Built by `scripts/build-enforcement.mjs` from DataSF: `yhqp-riqs` (sweep schedule, `$select: cnn,weekday,fromhour,tohour`), `3mea-di5p` (address→cnn), `ab4h-6ztd` (citations).

## 3. The join — confirmed viable via CNN

**Join key = CNN (raw).** The lucky alignment that makes this clean:
- curb keys everything by CNN, derived from **`yhqp-riqs`** — the exact street-sweeping dataset ParkLookup already ingests.
- ParkLookup's `extract_street_sweeping()` (`backend/pipeline_blockface.py`) already reads `weekday/fromhour/tohour` from that dataset — it just **drops `cnn` on the floor**. That dropped field is the join key.
- ParkLookup blockfaces are currently keyed only by `globalid` (a GUID, e.g. `{AEBFDC4F-...}`) with **no CNN** — that's why no join key exists in today's output.

So no fragile geometry matching is needed: the pipeline already spatially binds sweep rules to side-blockfaces; we just carry `cnn` through and look up `enforcement[cnn][jsDow(weekday)]`.

## 4. Concrete implementation

1. **Vendor** `enforcement.json` (+ keep its `_meta`/attribution; repo is MIT) into `backend/` alongside the pipeline.
2. **Preserve CNN** in `backend/pipeline_blockface.py` → `extract_street_sweeping()`:
   ```python
   "cnn": props.get("cnn"),   # currently discarded; this is the join key
   ```
3. **Stamp the window** in a post-join step keyed on `(cnn, weekday)`:
   ```
   ticketWindow = enforcement[str(cnn)][jsDow(weekday)]  # -> {count, avgMin, loMin, hiMin}
   ```
   Attach to the `streetCleaning` regulation (or the blockface). Omit when count is low/absent.
4. **Swift:** add `ticketWindow` to `Blockface.swift` (`BlockfaceRegulation`); surface in the result card
   ("Sweeping tickets here usually land ~12:15 PM (Mon), based on 815k citations").
5. Feeds the notification loop's **ticket-window-upcoming** (before `loMin`) and **ticket-window-started**
   (at `loMin`, `.timeSensitive`) stages — see `notification-loop-improvement-brief.md`.

## 5. Caveats
- **Sweeping enforcement only** — not meters/RPP. The feature is precisely curb.guide's headline.
- **Granularity:** per-CNN-segment, per-day — not per-side. Both side-blockfaces of a CNN share the window.
- **Coverage:** 10,462 CNN blocks (min 5 samples) vs ~18k blockfaces → some blocks show no window; degrade gracefully.
- **Static snapshot** (regenerate periodically, or rebuild from `ab4h-6ztd` later — but curb used a special records request for GPS-precise coords; the routine public feed geocodes more coarsely).
- **Timezone:** minutes-of-day are **America/Los_Angeles** — pin scheduling to that, not `Calendar.current`.
- **Framing:** historical, not predictive — present as "tickets *usually* land ~X," never a guarantee. Posted sign is source of truth.
- **License:** alevizio/curb is MIT (clean reuse w/ attribution); underlying data is SFMTA public record.

## 6. Recommended first step
Preserve `cnn`, run `pipeline_blockface.py` on the Mission District subset, and **measure real join coverage**
(what % of street-sweeping blockfaces get a `ticketWindow`) before touching Swift.
