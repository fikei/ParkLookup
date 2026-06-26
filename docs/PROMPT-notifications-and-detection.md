# Prompt — Notifications & Detection

Run locally in the ParkLookup repo (Xcode + a device). Branch:
`claude/curb-guide-integration-nif658`.

```
We're working in the ParkLookup iOS app (SFParkingZoneFinder). Stay on branch
claude/curb-guide-integration-nif658.

Read docs/notification-loop-improvement-brief.md first — it is the spec and
contains the current-state audit with file:line references. Implement it in two
stages, STOPPING for my review after Stage 1.

=== STAGE 1: Interactive notifications (no new permissions) ===
Today notifications have no buttons, don't fire in foreground, and tapping them
does nothing (the category "PARKING_ALERT" is set in
Core/Services/NotificationService.swift but never registered, and no
UNUserNotificationCenterDelegate exists anywhere). Fix all of that:

1. Add a UNUserNotificationCenterDelegate (in App/AppDelegate.swift or a new
   NotificationCoordinator) and set UNUserNotificationCenter.current().delegate
   at launch.
2. Register categories with actions via setNotificationCategories:
   - PARKING_ALERT (move-car/time-limit): MOVED_CAR, SNOOZE_15, DIRECTIONS(.foreground)
   - TICKET_WINDOW (street-sweeping): same actions, distinct copy
3. Implement delegate callbacks:
   - willPresent -> [.banner, .sound, .list]
   - didReceive response -> route on actionIdentifier:
       MOVED_CAR  -> ParkingSessionManager.endSession() + clear badge
       SNOOZE_15  -> reschedule this session's alerts +15 min
       DIRECTIONS -> open Apple Maps to session lat/lng (already in userInfo)
       default tap-> deep-link to ActiveParkingView for sessionId
4. content.interruptionLevel = .timeSensitive on the "at deadline"/"move now"
   alert; add the Time Sensitive Notifications entitlement. Do NOT use .critical.
5. Per-session threadIdentifier so alerts group.
6. Surface authorizationStatus != .authorized in the UI (today it's silent).

Constraints: ParkingSessionManager is @MainActor — keep actor boundaries correct
(delegate callbacks arrive off the main actor). Don't restructure scheduling
beyond what's needed. Build for a device target; manually verify: schedule a
near-future session, background the app, confirm action buttons appear, and that
MOVED_CAR ends the session and cancels remaining alerts. Then show me a diff and
STOP for review.

=== STAGE 2: Background auto-detection (after I approve Stage 1) ===
Implement Workstream B from the brief:
- Info.plist: add UIBackgroundModes=location and NSMotionUsageDescription; add an
  Always-location pre-permission explainer in onboarding.
- New ParkDetectionService: CLLocationManager.startMonitoringVisits() (primary
  wake source, survives termination) + startMonitoringSignificantLocationChanges()
  (secondary), confirmed by CMMotionActivityManager.queryActivityStarting(from:to:)
  for a drive->walk transition. Set allowsBackgroundLocationUpdates only after
  Always auth.
- On detection: one-shot high-accuracy requestLocation(), run
  ParkingDataAdapter.lookupParking(at:), then post a PARK_CONFIRM actionable
  notification ("Parked on <street>? Yes / Not now") that creates the session on
  Yes. (Auto-start as an opt-in setting.)
- AppDelegate didFinishLaunchingWithOptions: handle the location launch key and
  re-arm monitoring on every launch.
- Graceful fallback to the manual flow if the user stays on While-Using.

Test on a device across foreground / backgrounded / force-quit per the brief's
test matrix (background behavior can't be validated in Simulator alone).

For both stages: commit to the branch with clear messages. Do NOT open a PR or
merge. Bump no versions unless the brief says to.
```

Dependency note: the **ticket-window content** (Stage 1 step 2's TICKET_WINDOW copy
and the "ticket window upcoming/started" stages) needs the `ticketWindow` data from
the data-model migration (separate prompt). Wire the categories/actions now; the
ticket-window *content* lights up once that data lands.
