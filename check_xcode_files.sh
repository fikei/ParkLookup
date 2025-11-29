#!/bin/bash

echo "=== Files in Git but Missing from Xcode Build ==="
echo ""
echo "These files exist on disk but Xcode cannot find them."
echo "You need to add them to the Xcode project manually."
echo ""

echo "1. Core/Models:"
ls -1 SFParkingZoneFinder/SFParkingZoneFinder/Core/Models/*.swift 2>/dev/null | while read f; do
    echo "   - $(basename "$f")"
done

echo ""
echo "2. Core/Services:"
ls -1 SFParkingZoneFinder/SFParkingZoneFinder/Core/Services/*.swift 2>/dev/null | while read f; do
    echo "   - $(basename "$f")"
done

echo ""
echo "3. Features/Main/Views:"
ls -1 SFParkingZoneFinder/SFParkingZoneFinder/Features/Main/Views/*.swift 2>/dev/null | while read f; do
    echo "   - $(basename "$f")"
done

echo ""
echo "4. Features/Onboarding/Views:"
ls -1 SFParkingZoneFinder/SFParkingZoneFinder/Features/Onboarding/Views/*.swift 2>/dev/null | while read f; do
    echo "   - $(basename "$f")"
done

echo ""
echo "5. Resources:"
ls -1 SFParkingZoneFinder/SFParkingZoneFinder/Resources/*.json 2>/dev/null | while read f; do
    echo "   - $(basename "$f")"
done

echo ""
echo "=== Key Files That MUST Be in Xcode Project ==="
echo ""

files=(
    "SFParkingZoneFinder/SFParkingZoneFinder/Core/Services/ParkingDataAdapter.swift"
    "SFParkingZoneFinder/SFParkingZoneFinder/Core/Models/Blockface.swift"
    "SFParkingZoneFinder/SFParkingZoneFinder/Core/Models/ParkingSession.swift"
    "SFParkingZoneFinder/SFParkingZoneFinder/Core/Services/ParkingMeterLoader.swift"
    "SFParkingZoneFinder/SFParkingZoneFinder/Core/Services/NotificationService.swift"
    "SFParkingZoneFinder/SFParkingZoneFinder/Core/Services/ParkingSessionManager.swift"
    "SFParkingZoneFinder/SFParkingZoneFinder/Features/Main/Views/ActiveParkingView.swift"
    "SFParkingZoneFinder/SFParkingZoneFinder/Features/Onboarding/Views/NotificationPermissionView.swift"
    "SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ EXISTS: $file"
    else
        echo "❌ MISSING: $file"
    fi
done

echo ""
echo "=== How to Fix in Xcode ==="
echo ""
echo "Option 1 - Add Files Individually:"
echo "  1. Open Xcode"
echo "  2. Right-click on 'Core/Services' folder"
echo "  3. Select 'Add Files to SFParkingZoneFinder...'"
echo "  4. Navigate to and select ParkingDataAdapter.swift"
echo "  5. Check 'Copy items if needed' is OFF"
echo "  6. Check 'SFParkingZoneFinder' target is selected"
echo "  7. Click 'Add'"
echo "  8. Repeat for other folders/files"
echo ""
echo "Option 2 - Clean Build:"
echo "  1. Close Xcode"
echo "  2. Run: rm -rf ~/Library/Developer/Xcode/DerivedData/*"
echo "  3. Reopen Xcode"
echo "  4. Product → Clean Build Folder (Cmd+Shift+K)"
echo "  5. Product → Build (Cmd+B)"
echo ""
