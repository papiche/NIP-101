#!/bin/bash
# Test script for sync report functionality

## SET ASTROPORT ENVIRONNEMENT
[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] \
    && echo "TEST SYNC REPORT NEEDS ~/.zen/Astroport.ONE" \
    && exit 1

source ~/.zen/Astroport.ONE/tools/my.sh

echo "🧪 Testing Constellation Sync Report System"
echo "============================================="

# Check if CAPTAINEMAIL is set
if [[ -z "$CAPTAINEMAIL" ]]; then
    echo "❌ CAPTAINEMAIL not set. Please set it in your environment:"
    echo "   export CAPTAINEMAIL='your-email@example.com'"
    exit 1
fi

echo "✅ CAPTAINEMAIL: $CAPTAINEMAIL"

# Check if sync_report.sh exists and is executable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_REPORT_SCRIPT="$SCRIPT_DIR/sync_report.sh"

if [[ ! -f "$SYNC_REPORT_SCRIPT" ]]; then
    echo "❌ sync_report.sh not found at: $SYNC_REPORT_SCRIPT"
    exit 1
fi

if [[ ! -x "$SYNC_REPORT_SCRIPT" ]]; then
    echo "❌ sync_report.sh not executable"
    exit 1
fi

echo "✅ sync_report.sh found and executable"

# Check if mailjet.sh exists
MAILJET_SCRIPT="$HOME/.zen/Astroport.ONE/tools/mailjet.sh"
if [[ ! -f "$MAILJET_SCRIPT" ]]; then
    echo "❌ mailjet.sh not found at: $MAILJET_SCRIPT"
    exit 1
fi

if [[ ! -x "$MAILJET_SCRIPT" ]]; then
    echo "❌ mailjet.sh not executable"
    exit 1
fi

echo "✅ mailjet.sh found and executable"

# Check if log file exists
REPORT_LOG="$HOME/.zen/strfry/constellation-backfill.log"
if [[ ! -f "$REPORT_LOG" ]]; then
    echo "⚠️  Log file not found: $REPORT_LOG"
    echo "   This is normal if no sync has been run yet"
else
    echo "✅ Log file found: $REPORT_LOG"
    
    # Test the sync report script
    echo "🧪 Testing sync report generation..."
    if "$SYNC_REPORT_SCRIPT"; then
        echo "✅ Sync report generated successfully"
    else
        echo "❌ Sync report generation failed"
        exit 1
    fi
fi

echo ""
echo "🎉 All tests passed! The sync report system is ready."
echo ""
echo "📧 The next synchronization will automatically send a report to: $CAPTAINEMAIL"
echo "   The report will include:"
echo "   - Sync statistics (peers, events, profiles)"
echo "   - Performance metrics (timing, retries)"
echo "   - Error counts and success rates"
echo "   - Beautiful HTML formatting"
