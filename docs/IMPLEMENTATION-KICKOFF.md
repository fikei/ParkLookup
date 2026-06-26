# Local Implementation Kickoff

Paste the prompt below into Claude Code running locally in the ParkLookup repo
(full Xcode + device available) to start implementation. Branch is already
created: `claude/curb-guide-integration-nif658`.

Background docs to read first:
- `docs/notification-loop-improvement-brief.md` (the audit + full plan)
- `docs/curb-guide-ticket-window-integration.md` (the data feeding the ticket-window stages)

---

## Prompt — Phase 1: Interactive notifications

```
We're working in the ParkLookup iOS app (SFParkingZoneFinder). Stay on branch
claude/curb-guide-integration-nif658.

Read these two docs first — they're the spec:
- docs/notification-loop-improvement-brief.md
- docs/curb-guide-ticket-window-integration.md

Implement PHASE 1 ONLY from the brief: interactive notifications. Do NOT add any
new permissions or background modes yet (that's Phase 3). Scope:

1. Make the app a notification delegate. Add a UNUserNotificationCenterDelegate
   (in AppDelegate or a new NotificationCoordinator) and set
   UNUserNotificationCenter.current().delegate at launch in
   App/AppDelegate.swift didFinishLaunchingWithOptions.

2. Register notification categories with actions (currently the code sets
   categoryIdentifier = "PARKING_ALERT" in Core/Services/NotificationService.swift
   but never registers the category — fix that). Categories:
   - PARKING_ALERT (move-car / time-limit): MOVED_CAR, SNOOZE_15, DIRECTIONS(.foreground)
   - TICKET_WINDOW (street-sweeping): same actions, distinct copy
   Call setNotificationCategories with both.

3. Implement the delegate callbacks:
   - willPresent -> [.banner, .sound, .list] so alerts show in foreground
   - didReceive response -> route on actionIdentifier:
       MOVED_CAR  -> ParkingSessionManager.endSession() + clear badge
       SNOOZE_15  -> reschedule this session's alerts +15 min
       DIRECTIONS -> open Apple Maps to the session lat/lng (already in userInfo)
       default tap-> deep-link to ActiveParkingView for the sessionId

4. Add content.interruptionLevel = .timeSensitive to the "at deadline" / "move now"
   notification and add the Time Sensitive Notifications capability to the
   entitlements. (Do NOT use .critical.)

5. Set a per-session threadIdentifier so alerts group.

6. When authorizationStatus != .authorized, surface it in the UI instead of only
   logging (today failures are silent).

Constraints:
- ParkingSessionManager is @MainActor — keep actor boundaries correct; the
  delegate callbacks come in on arbitrary threads.
- Don't refactor the detection/scheduling beyond what Phase 1 needs.
- Build for an iOS device target and confirm it compiles. Manually verify on a
  device or simulator: schedule a near-future session, background the app, confirm
  the notification shows action buttons, and that MOVED_CAR ends the session and
  cancels the remaining alerts.

When it builds and the actions work, show me a summary and a diff. Commit to the
branch with clear messages, but do NOT open a PR or merge.
```

---

## After Phase 1
- **Phase 2 (ticket-window stages):** implement the curb.guide `ticketWindow` join
  (`docs/curb-guide-ticket-window-integration.md`) — preserve `cnn` in
  `backend/pipeline_blockface.py`, measure join coverage on the Mission District
  subset, then add the `TICKET_WINDOW` upcoming/started notifications.
- **Phase 3 (background detection):** Always-location + CLVisit + Core Motion, per
  the brief's Workstream B. The real lift; do last.
