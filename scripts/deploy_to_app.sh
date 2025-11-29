#!/bin/bash
# Deploy processed blockface data to iOS app resources
#
# Usage:
#   ./scripts/deploy_to_app.sh mission    # Deploy Mission District test data
#   ./scripts/deploy_to_app.sh full       # Deploy full SF data

set -e  # Exit on error

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_RESOURCES="$PROJECT_ROOT/SFParkingZoneFinder/SFParkingZoneFinder/Resources"

case "${1:-mission}" in
    mission)
        SOURCE="$PROJECT_ROOT/data/processed/mission_district/sample_blockfaces_sideaware_full.json"
        echo "📍 Deploying Mission District test data (1,469 blockfaces, ~2.8MB)"
        ;;
    full)
        SOURCE="$PROJECT_ROOT/data/processed/full_sf/blockfaces_full_sf.json"
        echo "🌉 Deploying FULL San Francisco data (18,355 blockfaces, ~35MB)"
        ;;
    *)
        echo "Usage: $0 [mission|full]"
        exit 1
        ;;
esac

if [ ! -f "$SOURCE" ]; then
    echo "❌ ERROR: Source file not found: $SOURCE"
    echo ""
    if [[ "$1" == "full" ]]; then
        echo "Run this first to generate full SF data:"
        echo "  python3 scripts/run_full_sf_conversion.py"
    else
        echo "Run this first to generate Mission District data:"
        echo "  python3 scripts/run_full_conversion.py"
    fi
    exit 1
fi

DEST="$APP_RESOURCES/sample_blockfaces.json"

echo "Source: $SOURCE"
echo "Dest:   $DEST"
echo ""

# Show file info
echo "Source file info:"
ls -lh "$SOURCE"
BLOCKFACE_COUNT=$(jq -r '.blockfaces | length' "$SOURCE")
echo "Blockface count: $BLOCKFACE_COUNT"
echo ""

# Copy with confirmation
read -p "Deploy to app? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cp "$SOURCE" "$DEST"
    echo "✅ Deployed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Open Xcode and build the app"
    echo "2. Test on simulator or device"
    echo "3. Verify regulations display correctly"
else
    echo "❌ Deployment cancelled"
fi
