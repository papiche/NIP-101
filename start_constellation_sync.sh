#!/bin/bash
# Astroport constellation synchronization startup script
# This script starts strfry router for inter-relay synchronization

## SET ASTROPORT ENVIRONNEMENT
[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] \
    && echo "STRFRY CONSTELLATION SYNC NEEDS ~/.zen/Astroport.ONE" \
    && exit 1

source ~/.zen/Astroport.ONE/tools/my.sh

# Configuration file path
ROUTER_CONFIG="$HOME/.zen/strfry/strfry-router.conf"

# Check if router config exists
if [[ ! -f "$ROUTER_CONFIG" ]]; then
    echo "Error: Router configuration not found: $ROUTER_CONFIG"
    echo "Please run setup.sh first to create the configuration"
    exit 1
fi

# Check if strfry binary exists
STRFRY_BIN="$HOME/.zen/strfry/strfry"
if [[ ! -x "$STRFRY_BIN" ]]; then
    echo "Error: strfry binary not found or not executable: $STRFRY_BIN"
    exit 1
fi

# Check if constellation sync is already running
PID_FILE="$HOME/.zen/strfry/constellation-sync.pid"
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Constellation synchronization is already running (PID: $PID)"
        echo "To stop it, run: ./stop_constellation_sync.sh"
        exit 0
    else
        echo "Removing stale PID file"
        rm -f "$PID_FILE"
    fi
fi

echo "Starting Astroport constellation synchronization..."
echo "Router config: $ROUTER_CONFIG"
echo "Logs will be written to: $HOME/.zen/strfry/constellation-sync.log"

# Start strfry router in background (must run from strfry directory)
cd "$(dirname "$STRFRY_BIN")"
nohup "$STRFRY_BIN" router "$(basename "$ROUTER_CONFIG")" > "$HOME/.zen/strfry/constellation-sync.log" 2>&1 &
ROUTER_PID=$!

# Save PID
echo "$ROUTER_PID" > "$PID_FILE"

# Wait a moment to check if it started successfully
sleep 2
if kill -0 "$ROUTER_PID" 2>/dev/null; then
    echo "✅ Constellation synchronization started successfully (PID: $ROUTER_PID)"
    echo "To monitor logs: tail -f $HOME/.zen/strfry/constellation-sync.log"
    echo "To stop: ./stop_constellation_sync.sh"
else
    echo "❌ Failed to start constellation synchronization"
    rm -f "$PID_FILE"
    exit 1
fi
