#!/bin/bash
#
# Update iOS app bundled parking data from pipeline output
#
# Usage:
#   ./update_ios_data.sh              # Run pipeline + convert
#   ./update_ios_data.sh --convert    # Convert only (skip fetching)
#   ./update_ios_data.sh --skip-meters # Run pipeline without meters
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_RESOURCES="$SCRIPT_DIR/../SFParkingZoneFinder/SFParkingZoneFinder/Resources"
OUTPUT_DIR="$SCRIPT_DIR/output"

echo "=========================================="
echo "SF Parking Data Update Script"
echo "=========================================="
echo ""

# Check Python environment
if [ ! -d "$SCRIPT_DIR/venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$SCRIPT_DIR/venv"
fi

source "$SCRIPT_DIR/venv/bin/activate"

# Install dependencies if needed
if ! pip show aiohttp &> /dev/null; then
    echo "Installing dependencies..."
    pip install -r "$SCRIPT_DIR/requirements.txt"
fi

# Parse arguments
CONVERT_ONLY=false
SKIP_METERS=""

for arg in "$@"; do
    case $arg in
        --convert)
            CONVERT_ONLY=true
            ;;
        --skip-meters)
            SKIP_METERS="--skip-meters"
            ;;
    esac
done

# Run pipeline (unless convert-only)
if [ "$CONVERT_ONLY" = false ]; then
    echo ""
    echo "Step 1: Running data pipeline..."
    echo "----------------------------------------"
    python "$SCRIPT_DIR/pipeline.py" $SKIP_METERS

    if [ $? -ne 0 ]; then
        echo "ERROR: Pipeline failed!"
        exit 1
    fi
fi

# Convert to iOS format
echo ""
echo "Step 2: Converting to iOS format..."
echo "----------------------------------------"
python "$SCRIPT_DIR/convert_to_ios.py"

if [ $? -ne 0 ]; then
    echo "ERROR: Conversion failed!"
    exit 1
fi

# Show result
echo ""
echo "=========================================="
echo "Update complete!"
echo "=========================================="
echo ""
echo "iOS data file updated:"
echo "  $IOS_RESOURCES/sf_parking_zones.json"
echo ""
echo "Next steps:"
echo "  1. Build and run the iOS app in Xcode"
echo "  2. Verify zone data displays correctly"
echo "  3. Test zone lookup at known locations"
echo ""

# Show data stats
if [ -f "$IOS_RESOURCES/sf_parking_zones.json" ]; then
    ZONE_COUNT=$(grep -c '"id":' "$IOS_RESOURCES/sf_parking_zones.json" 2>/dev/null || echo "?")
    VERSION=$(grep '"version"' "$IOS_RESOURCES/sf_parking_zones.json" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
    echo "Data stats:"
    echo "  Version: $VERSION"
    echo "  Zones: ~$ZONE_COUNT"
fi
