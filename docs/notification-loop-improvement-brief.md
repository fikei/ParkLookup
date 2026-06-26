# Brief: Park-Detect → Ticket-Window → Move-Car Notification Loop

**Scope:** Audit the current parking-notification loop and specify the work to (1) convert it to **interactive notifications** and (2) move **core park-detection into the background** so the loop runs with the app suspended or terminated.

**Status:** Proposal / engineering brief. No code changed yet.
**Related:** the validated curb.guide `ticketWindow` join (per-CNN × day-of-week street-sweeping citation timing) feeds the "ticket window" stages below.

---

## 1. The loop we want

```
[park detect] ──▶ [ticket window upcoming] ──▶ [ticket window started] ──▶ [move car]
   auto,            "sweeping tickets here          "ticketing has              actionable:
   background        usually start ~12:02"           started on your block"     Moved it / Snooze / Directions
```

Four stages. Each should fire reliably while the app is **backgrounded or fully closed**, and each user-facing alert should be **actionable from the lock screen** without opening the app.

---

## 2. Current-state audit (what exists today)

All paths below are under `SFParkingZoneFinder/SFParkingZoneFinder/`.

### Stage 1 — Park detect: **manual only**
- The only way a session starts is the user tapping "Start parking session" in the UI → `MainResultViewModel.startParkingSession()` / `startParkingSessionAt(...)` (`Features/Main/ViewModels/MainResultViewModel.swift:290,317`) → `ParkingSessionManager.startSession(...)`.
- `LocationService` (`Core/Services/LocationService.swift`) only does `requestWhenInUseAuthorization()` + `startUpdatingLocation()` / `requestLocation()`. **Foreground only.**
- **No** `requestAlwaysAuthorization`, `startMonitoringVisits`, `startMonitoringSignificantLocationChanges`, `allowsBackgroundLocationUpdates`, or any `CMMotionActivity` usage anywhere in the codebase (verified by grep — "NONE FOUND").
- `Info.plist` has **no `UIBackgroundModes`** and **no `NSMotionUsageDescription`**. The `NSLocationAlwaysAndWhenInUseUsageDescription` string is present but unused — nothing ever requests Always.

> Result: there is no "park detect" today. The loop is entirely user-initiated and dies the moment the app is suspended.

### Stages 2–4 — Notifications: **scheduled, but static and non-interactive**
`Core/Services/NotificationService.swift` + `Core/Services/ParkingSessionManager.swift`:
- On `startSession`, `scheduleSessionNotifications(for:)` schedules up to three `UNCalendarNotificationTrigger`s relative to `session.parkUntil`: `oneHour` (−60m), `fifteenMinutes` (−15m), `atDeadline` (0). (`NotificationTiming`, `Core/Models/ParkingSession.swift:132`).
- `session.parkUntil` = **`min` of every rule's deadline** (`ParkingSession.swift:16`). This conflates distinct deadlines — a time-limit/RPP "move your car" deadline and a street-cleaning "ticket window" are collapsed into one number, so we cannot message them differently.
- `content.categoryIdentifier = "PARKING_ALERT"` is set (`NotificationService.swift:71`) **but the category is never registered** — no `setNotificationCategories(...)` exists anywhere.
- **No `UNUserNotificationCenterDelegate` is set anywhere.** `AppDelegate` (`App/AppDelegate.swift`) only configures Google Maps; `SFParkingZoneFinderApp` just adapts it. Consequences:
  - **No action buttons** appear (category unregistered) → nothing is "interactive."
  - **No `didReceive response`** → tapping the notification or any action does nothing beyond launching the app; it does **not** deep-link to the session, end it, or open directions.
  - **No `willPresent`** → notifications are **suppressed while the app is foregrounded**.
- Permission request is `[.alert, .sound, .badge]` only (`NotificationService.swift:23`). No `interruptionLevel` is ever set, so a "move now" alert is silently swallowed by Focus / Do Not Disturb. No provisional/time-sensitive handling.
- Failure modes are log-only (`logger.warning`); a denied/limited authorization is invisible to the user.

### Loop mapping (today)
| Stage | Today | Gap |
|---|---|---|
| park detect | manual tap only | no background/auto detection at all |
| ticket window upcoming | generic "Move Your Car Soon" at parkUntil−1h | not tied to sweeping ticket data; generic copy; no action |
| ticket window started | "Move Your Car Now" at parkUntil | conflated deadline; no action; Focus can mute it |
| move car | same notification | can't confirm "moved" / snooze / get directions from the alert |

---

## 3. Target architecture

Two workstreams. They are independent and can ship in either order, but together they close the loop.

### Workstream A — Interactive, intent-rich notifications
1. **Register a notification delegate + categories at launch.**
   - Make `AppDelegate` (or a dedicated `NotificationCoordinator`) conform to `UNUserNotificationCenterDelegate` and set `UNUserNotificationCenter.current().delegate` in `didFinishLaunchingWithOptions`.
   - Register two categories with actions:
     - `PARKING_ALERT` (move-car / time-limit): `MOVED_CAR` (ends session, cancels remaining), `SNOOZE_15` (reschedule +15m), `DIRECTIONS` (`.foreground`, opens Apple/Google Maps to `session.location`).
     - `TICKET_WINDOW` (street-sweeping): same actions; distinct copy.
   - Use `UNNotificationAction`/`UNNotificationActionIcon`; mark `DIRECTIONS` `.foreground`, others background-safe (no unlock needed for `MOVED_CAR`/`SNOOZE`).
2. **Implement the delegate callbacks.**
   - `willPresent` → return `[.banner, .sound, .list]` so alerts show in-foreground.
   - `didReceive response` → switch on `response.actionIdentifier`:
     - `MOVED_CAR` → `ParkingSessionManager.endSession()` (cancels pending) + clear badge.
     - `SNOOZE_15` → reschedule this session's alerts +15 min.
     - `DIRECTIONS` → open maps to `userInfo` lat/lng (already present, `NotificationService.swift:75`).
     - default/tap → deep-link to `ActiveParkingView` for `sessionId`.
3. **Time-sensitive delivery.** Set `content.interruptionLevel = .timeSensitive` on "ticket window started" / "move now" so they pierce Focus. Add the **Time Sensitive Notifications** capability to the entitlements. (Avoid `.critical` — requires a special Apple entitlement and is overkill.)
4. **Distinct threads + relevance.** Set `threadIdentifier` per session and per stage (move-car vs ticket-window) so alerts group sensibly; set `relevanceScore`/`UNNotificationContentProviding` for the summary.
5. **Surface permission state.** When `authorizationStatus != .authorized`, drive a UI affordance instead of only logging.

### Workstream B — Background park-detection
1. **Capabilities & strings (Info.plist / entitlements).**
   - Add `UIBackgroundModes` → `location` (and `processing` if we later add a `BGProcessingTask` refresh).
   - Add `NSMotionUsageDescription` (currently missing — Core Motion will crash without it).
   - Keep/clarify `NSLocationAlwaysAndWhenInUseUsageDescription`; add a pre-permission explainer screen.
2. **Detection pipeline (primary path).**
   - `CLLocationManager.startMonitoringVisits()` as the wake source — purpose-built for "arrived and the trip ended," low-power, and **relaunches the app after termination/force-quit** via `UIApplication.LaunchOptionsKey.location`.
   - On a `CLVisit` with a finite `arrivalDate`/`departureDate` pattern indicating a stop, confirm it was a drive→park using `CMMotionActivityManager.queryActivityStarting(from:to:)` over the preceding minutes (motion is logged by the coprocessor even while suspended — no need to have been running).
   - Use `startMonitoringSignificantLocationChanges()` as a secondary/redundant wake source.
   - Set `allowsBackgroundLocationUpdates = true` **only** once `Always` auth is granted; never start continuous GPS in the background.
3. **Refine to block precision on wake.** Visit/significant coordinates are cell/Wi-Fi-grade (can be a block off). On wake, fire one `requestLocation()` (high accuracy) within the brief background window, then run `ParkingDataAdapter.lookupParking(at:)` to resolve the blockface — block-side precision matters for sweeping rules.
4. **Confirm before committing (consent-friendly).** Rather than silently auto-starting a session, post a `PARK_CONFIRM` actionable notification: "Parked on \<street\>? — Yes / Not now." "Yes" creates the session and schedules the stage-2/3/4 alerts. (Auto-start as a setting for power users.)
5. **Relaunch handling.** In `didFinishLaunchingWithOptions`, detect the location launch key, rebuild the location stack, and **always re-arm visit/significant monitoring** on every launch (monitoring must be restarted after relaunch; after a device reboot it resumes only post-unlock).
6. **Permission escalation & downgrade.** Pre-prompt → `requestAlwaysAuthorization`. If the user stays on "While Using" or downgrades, fall back gracefully to the existing manual flow and surface why background alerts won't fire.

---

## 4. Concrete change list (files)

| Area | File | Change |
|---|---|---|
| Delegate + categories | `App/AppDelegate.swift` | conform to `UNUserNotificationCenterDelegate`; set delegate; `setNotificationCategories`; implement `willPresent` + `didReceive` |
| Action routing | `Core/Services/ParkingSessionManager.swift` | add `handleAction(_:for:)` → end/snooze/restore; expose reschedule(+15m) |
| Content | `Core/Services/NotificationService.swift` | set `interruptionLevel`, `threadIdentifier`; split move-car vs ticket-window copy; build `TICKET_WINDOW` requests from `ticketWindow` data |
| Deadlines | `Core/Models/ParkingSession.swift` | stop collapsing all deadlines into one `parkUntil`; model move-car deadline and ticket-window (loMin/avgMin) as separate scheduled events |
| Detection | `Core/Services/LocationService.swift` (+ new `ParkDetectionService.swift`) | visits + significant-change + motion confirmation; `requestAlwaysAuthorization`; `allowsBackgroundLocationUpdates` |
| Launch | `App/AppDelegate.swift` / `SFParkingZoneFinderApp.swift` | handle location-key relaunch; re-arm monitoring |
| Config | `Info.plist`, `*.entitlements` | `UIBackgroundModes=location`; `NSMotionUsageDescription`; Time Sensitive Notifications capability |
| Onboarding | `Features/Onboarding/...` | Always-location pre-prompt; explain background alerts |

---

## 5. Phasing

- **Phase 1 — Interactive notifications (no new permissions).** Workstream A 1–5. Self-contained, shippable, immediately improves the existing manual flow. ~1–2 days.
- **Phase 2 — Ticket-window stages.** Wire the validated curb.guide `ticketWindow` (loMin/avgMin/hiMin per CNN×dow) into distinct "upcoming" (T-? before `loMin`) and "started" (at `loMin`, `.timeSensitive`) notifications. Depends on the `ticketWindow` join landing. ~1 day.
- **Phase 3 — Background detection.** Workstream B. The real lift (Always-permission UX + accuracy recovery + relaunch handling + App Review justification). ~3–5 days incl. on-device testing.

---

## 6. Risks & caveats
- **Always-location consent** is the gating risk: lower opt-in, App Review scrutiny, periodic iOS re-prompts. Manual flow must remain first-class.
- **Detection precision:** visit/significant coordinates can land on the wrong block-side; always refine with a one-shot fix and let the user nudge the pin. Auto-detection augments, not replaces, the manual tap.
- **Battery & false positives:** prefer visits over continuous GPS; require the motion drive→walk confirmation to suppress false "parks" (e.g., stopped at a light).
- **64 pending-notification cap:** fine at our volume, but reschedule idempotently on launch/wake since `ticketWindow` data may refine.
- **Time zone:** ticket-window minutes-of-day are local SF time — pin scheduling to `America/Los_Angeles`, not just `Calendar.current`.
- **No-deadline sessions:** today a session with no rule deadline schedules nothing; ensure street-cleaning next-occurrence and ticket-window produce real fire dates.

---

## 7. Test matrix (on device — background work can't be validated in Simulator alone)
| Scenario | Foreground | Backgrounded | Force-quit | Post-reboot |
|---|---|---|---|---|
| Park detected → confirm notification | ✓ | ✓ | ✓ (relaunch) | ✓ (after unlock) |
| Ticket-window-upcoming fires | ✓ | ✓ | ✓ | ✓ |
| Ticket-window-started (.timeSensitive vs Focus) | ✓ | ✓ | ✓ | ✓ |
| "Moved my car" ends session + cancels pending | ✓ | ✓ | ✓ | n/a |
| "Snooze 15" reschedules | ✓ | ✓ | ✓ | n/a |
| "Directions" opens maps to car | ✓ | ✓ | ✓ | n/a |
| Always→WhileUsing downgrade falls back to manual | ✓ | ✓ | — | — |
