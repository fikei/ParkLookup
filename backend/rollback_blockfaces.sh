#!/bin/bash
# Rollback script for blockface data
# Usage: ./rollback_blockfaces.sh

IOS_RESOURCES="../SFParkingZoneFinder/SFParkingZoneFinder/Resources"
CURRENT="$IOS_RESOURCES/sample_blockfaces.json"
BACKUP="$IOS_RESOURCES/sample_blockfaces.backup.json"
TEMP="$IOS_RESOURCES/sample_blockfaces.temp.json"

echo "🔄 Blockface Data Rollback"
echo "=========================="

# Check if backup exists
if [ ! -f "$BACKUP" ]; then
    echo "❌ Error: Backup file not found at $BACKUP"
    exit 1
fi

echo "📦 Current file: $(ls -lh "$CURRENT" | awk '{print $5}')"
echo "💾 Backup file:  $(ls -lh "$BACKUP" | awk '{print $5}')"
echo ""

# Confirm rollback
read -p "⚠️  Replace current data with backup? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Rollback cancelled"
    exit 0
fi

# Perform rollback
echo "🔄 Creating temporary backup of current file..."
cp "$CURRENT" "$TEMP"

echo "🔄 Restoring backup..."
cp "$BACKUP" "$CURRENT"

echo "✅ Rollback complete!"
echo ""
echo "Current file restored from backup"
echo "Old current file saved to: sample_blockfaces.temp.json"
echo ""
echo "To undo this rollback, run:"
echo "  cp $TEMP $CURRENT"
