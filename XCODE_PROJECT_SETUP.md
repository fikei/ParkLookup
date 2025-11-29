# Xcode Project File Configuration Issue

## Problem
Build errors indicate that Xcode cannot find types that exist in the codebase:
- `ParkingDataAdapter` (exists in Core/Services/)
- `ParkingMeter` types (now consolidated in ParkingMeterLoader.swift)
- Other restored files may have similar issues

## Root Cause
The restored Swift files were added via git, but Xcode's `project.pbxproj` file doesn't know about them. They need to be added to the Xcode project's build phases.

## Files That Need to Be Added to Xcode Project

### Already in Git (Need Xcode Registration):
1. `Core/Models/Blockface.swift`
2. `Core/Models/ParkingSession.swift`
3. `Core/Services/NotificationService.swift`
4. `Core/Services/ParkingSessionManager.swift`
5. `Core/Services/ParkingMeterLoader.swift` (contains ParkingMeter types)
6. `Features/Main/Views/ActiveParkingView.swift`
7. `Features/Onboarding/Views/NotificationPermissionView.swift`
8. `Resources/sample_blockfaces.json`

### File That Should Be Removed from Xcode:
9. `Core/Models/ParkingMeter.swift` (DELETED - types moved to ParkingMeterLoader.swift)

## How to Fix in Xcode

### Option 1: Add Files Manually
1. Open the Xcode project
2. Right-click on each folder (Core/Models, Core/Services, etc.)
3. Select "Add Files to Project..."
4. Select the missing files
5. Ensure "Add to targets" includes your app target
6. Build and verify

### Option 2: Remove and Re-add Project Reference
1. Close Xcode
2. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData/*`
3. Open Xcode
4. Clean build folder (Cmd+Shift+K)
5. Build (Cmd+B)

### Option 3: Fix project.pbxproj Directly (Advanced)
If comfortable with pbxproj format, you can manually add file references.
This is error-prone and not recommended.

## Verification
After fixing, these should compile without errors:
```swift
import Foundation

// Should find these types:
let adapter = ParkingDataAdapter.shared
let meter: ParkingMeter = ...
let blockface: Blockface = ...
let session: ParkingSession = ...
let notification = NotificationService()
```

## Current Branch Status
All Swift source files have been restored from git history and are present
in the file system. Only Xcode project configuration is missing.

Branch: `claude/fix-block-face-colors-01FzcFoJ8L7eTjuRMhZyZUQg`
Commits: 6 total (color fix, data restore, file restoration, dependency injection)
