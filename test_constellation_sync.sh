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

# Check router configuration
ROUTER_CONFIG="$HOME/.zen/strfry/strfry-router.conf"
if [[ -f "$ROUTER_CONFIG" ]]; then
    echo "✅ Router configuration found: $ROUTER_CONFIG"
    
    # Check constellation peers
    PEERS=$(grep -o '"[^"]*"' "$ROUTER_CONFIG" | grep -v "constellation" | grep -v "both" | grep -v "0, 1, 3, 22242" | grep -v "1000")
    if [[ -n "$PEERS" ]]; then
        echo "   ✅ Constellation peers configured:"
        echo "$PEERS" | sed 's/^/      /'
    else
        echo "   ⚠️  No constellation peers found"
    fi
    
    # Check direction
    if grep -q "dir = \"both\"" "$ROUTER_CONFIG"; then
        echo "   ✅ Bidirectional synchronization enabled"
    else
        echo "   ⚠️  Bidirectional synchronization not configured"
    fi
else
    echo "❌ Router configuration not found: $ROUTER_CONFIG"
    echo "   Run setup.sh to create the configuration"
    exit 1
fi

# Check if constellation sync is running
PID_FILE="$HOME/.zen/strfry/constellation-sync.pid"
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "✅ Constellation synchronization is running (PID: $PID)"
        
        # Check process details
        PROCESS_INFO=$(ps -p "$PID" -o pid,ppid,cmd --no-headers 2>/dev/null)
        if [[ -n "$PROCESS_INFO" ]]; then
            echo "   Process info: $PROCESS_INFO"
        fi
    else
        echo "⚠️  PID file exists but process is not running"
        echo "   Consider removing stale PID file: $PID_FILE"
    fi
else
    echo "ℹ️  Constellation synchronization is not running"
    echo "   To start: ./start_constellation_sync.sh"
fi

# Check logs
LOG_FILE="$HOME/.zen/strfry/constellation-sync.log"
if [[ -f "$LOG_FILE" ]]; then
    echo "✅ Log file exists: $LOG_FILE"
    LOG_SIZE=$(du -h "$LOG_FILE" | cut -f1)
    echo "   Log size: $LOG_SIZE"
    
    # Show last few log lines
    echo "   Last log entries:"
    tail -5 "$LOG_FILE" | sed 's/^/      /'
else
    echo "ℹ️  No log file yet (will be created when sync starts)"
fi

echo ""
echo "🔧 Configuration Summary:"
echo "========================="
echo "Main config: $MAIN_CONFIG"
echo "Router config: $ROUTER_CONFIG"
echo "Start script: ./start_constellation_sync.sh"
echo "Stop script: ./stop_constellation_sync.sh"
echo "Test script: ./test_constellation_sync.sh"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo ""
    echo "🚀 Constellation synchronization is ACTIVE and running!"
else
    echo ""
    echo "⏸️  Constellation synchronization is INACTIVE"
    echo "   Run ./start_constellation_sync.sh to start synchronization"
fi
