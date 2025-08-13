#!/bin/bash
# Test script for Astroport constellation synchronization

echo "🧪 Testing Astroport Constellation Synchronization Configuration"
echo "================================================================"

# Check if strfry binary exists
STRFRY_BIN="$HOME/.zen/strfry/strfry"
if [[ -x "$STRFRY_BIN" ]]; then
    echo "✅ strfry binary found: $STRFRY_BIN"
    echo "   Version: $($STRFRY_BIN --version 2>&1 | head -1)"
else
    echo "❌ strfry binary not found or not executable: $STRFRY_BIN"
    exit 1
fi

# Check main configuration
MAIN_CONFIG="$HOME/.zen/strfry/strfry.conf"
if [[ -f "$MAIN_CONFIG" ]]; then
    echo "✅ Main strfry configuration found: $MAIN_CONFIG"
    
    # Check key configuration values
    if grep -q "bind = \"0.0.0.0\"" "$MAIN_CONFIG"; then
        echo "   ✅ Bind address: 0.0.0.0 (external access enabled)"
    else
        echo "   ⚠️  Bind address not set to 0.0.0.0"
    fi
    
    if grep -q "port = 7777" "$MAIN_CONFIG"; then
        echo "   ✅ Port: 7777"
    else
        echo "   ⚠️  Port not set to 7777"
    fi
else
    echo "❌ Main strfry configuration not found: $MAIN_CONFIG"
    exit 1
fi

# Check backfill script
BACKFILL_SCRIPT="$HOME/.zen/workspace/NIP-101/backfill_constellation.sh"
if [[ -f "$BACKFILL_SCRIPT" ]]; then
    echo "✅ Backfill script found: $BACKFILL_SCRIPT"
    
    if [[ -x "$BACKFILL_SCRIPT" ]]; then
        echo "   ✅ Backfill script is executable"
    else
        echo "   ⚠️  Backfill script is not executable"
    fi
else
    echo "❌ Backfill script not found: $BACKFILL_SCRIPT"
    exit 1
fi

# Check if constellation trigger is configured
TRIGGER_SCRIPT="$HOME/.zen/workspace/NIP-101/constellation_sync_trigger.sh"
if [[ -f "$TRIGGER_SCRIPT" ]]; then
    echo "✅ Constellation trigger script found: $TRIGGER_SCRIPT"
    
    if [[ -x "$TRIGGER_SCRIPT" ]]; then
        echo "   ✅ Trigger script is executable"
    else
        echo "   ⚠️  Trigger script is not executable"
    fi
else
    echo "ℹ️  Constellation trigger script not found: $TRIGGER_SCRIPT"
fi

# Check backfill logs
BACKFILL_LOG="$HOME/.zen/strfry/constellation-backfill.log"
if [[ -f "$BACKFILL_LOG" ]]; then
    echo "✅ Backfill log file exists: $BACKFILL_LOG"
    LOG_SIZE=$(du -h "$BACKFILL_LOG" | cut -f1)
    echo "   Log size: $LOG_SIZE"
    
    # Show last few log lines
    echo "   Last log entries:"
    tail -5 "$BACKFILL_LOG" | sed 's/^/      /'
else
    echo "ℹ️  No backfill log file yet (will be created when backfill runs)"
fi

# Check trigger logs
TRIGGER_LOG="$HOME/.zen/strfry/constellation-trigger.log"
if [[ -f "$TRIGGER_LOG" ]]; then
    echo "✅ Trigger log file exists: $TRIGGER_LOG"
    LOG_SIZE=$(du -h "$TRIGGER_LOG" | cut -f1)
    echo "   Log size: $LOG_SIZE"
    
    # Show last few log lines
    echo "   Last log entries:"
    tail -5 "$TRIGGER_LOG" | sed 's/^/      /'
else
    echo "ℹ️  No trigger log file yet (will be created when trigger runs)"
fi

echo ""
echo "🔧 Configuration Summary:"
echo "========================="
echo "Main config: $MAIN_CONFIG"
echo "Backfill script: $BACKFILL_SCRIPT"
echo "Trigger script: $TRIGGER_SCRIPT"
echo "Test script: ./test_constellation_sync.sh"

# Check last sync status
LAST_SYNC_FILE="$HOME/.zen/strfry/last_constellation_sync"
if [[ -f "$LAST_SYNC_FILE" ]]; then
    LAST_SYNC=$(cat "$LAST_SYNC_FILE")
    echo ""
    echo "📅 Last constellation backfill: $LAST_SYNC"
    echo "🚀 Constellation backfill system is CONFIGURED and ready!"
else
    echo ""
    echo "⏸️  No constellation backfill has been executed yet"
    echo "   The system will run automatically after 12:00 via _12345.sh"
fi
