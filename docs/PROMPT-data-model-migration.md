# Prompt — Data-Model Migration (curb.guide integration)

Run locally in the ParkLookup repo (Python for the pipeline + Xcode). Branch:
`claude/curb-guide-integration-nif658`.

```
We're working in ParkLookup (iOS app + Python backend pipeline). Stay on branch
claude/curb-guide-integration-nif658.

Read these two docs first — they are the spec:
- docs/PRD-curb-guide-data-model-integration.md   (the plan + decision)
- docs/curb-guide-ticket-window-integration.md    (the data + the CNN join)

Implement the GRACEFUL-ENRICHMENT approach from the PRD (Option A — do NOT re-key
the model to CNN). Work in this order and validate coverage before touching Swift.

=== Step 1: Pipeline (backend/pipeline_blockface.py) ===
- Vendor curb.guide's enforcement.json into backend/ (from
  https://github.com/alevizio/curb, MIT) and keep its _meta/attribution.
- Preserve the join key: add "cnn" to each blockface, and in
  extract_street_sweeping() keep "cnn" from the source sweep record (yhqp-riqs)
  — it's currently dropped.
- Post-join: for each streetCleaning regulation, look up
  enforcement[str(cnn)][str(jsDow(weekday))] = [count, avgMin, loMin, hiMin] and,
  when count >= MIN_SAMPLES, attach:
      reg["ticketWindow"] = {count, avgMin, loMin, hiMin}
  Omit when missing/low-sample. (jsDow: Sun=0..Sat=6.)
- Wrap output as { schemaVersion: 2, meta: {...provenance...}, blockfaces: [...] }.
- Run on the Mission District subset and REPORT coverage: what % of
  street-cleaning blockfaces got a ticketWindow, and what % of CNNs in
  enforcement.json matched a blockface. Show me these numbers before continuing.

=== Step 2: Swift model (Core/Models/Blockface.swift) ===
- Add `let cnn: String?` to Blockface.
- Add `struct TicketWindow: Codable, Hashable { count; avgMin; loMin; hiMin }`
  (minutes are SF-local).
- Add `let cnn: String?` and `let ticketWindow: TicketWindow?` to
  BlockfaceRegulation — AND add `cnn, ticketWindow` to its explicit CodingKeys
  (easy to miss; the enum is explicit so omitting them silently drops the fields).
- Decode all new fields with decodeIfPresent so legacy files still load.
- Update BlockfaceDataResponse to decodeIfPresent schemaVersion/meta.

=== Step 3: Timezone correctness ===
- Fix BlockfaceRegulation.isInEffect(at:) to use a fixed America/Los_Angeles
  Calendar instead of Calendar.current, and add a TicketWindow helper that maps
  avgMin/loMin/hiMin to a Date interval for the next sweep occurrence in SF time.

=== Step 4: Rollout safety ===
- Add the enriched dataset as a NEW DeveloperSettings.blockfaceDataSource option
  (don't replace the default yet) so it can be A/B'd.
- Add a decode test with two fixtures: the legacy file (no cnn/ticketWindow) and
  the enriched file — both must decode without error.

Constraints: no UI changes in this prompt (the result card / notification copy is
a separate workstream). Keep globalid as the canonical id — do not touch overrides,
sessions, or map overlays. Commit to the branch with clear messages; do NOT open a
PR or merge.

When done, show me: the coverage numbers from Step 1, a diff, and confirmation the
decode test passes on both fixtures.
```
